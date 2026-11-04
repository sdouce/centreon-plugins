#
# Copyright 2026-Present Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package hardware::server::ibm::hmc::restapi::mode::vioserrors;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::misc qw/is_excluded/;
use centreon::plugins::constants qw(:counters);
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold_ng);
use POSIX qw(strftime);
use Time::Local qw(timelocal);

sub prefix_vios_output {
    my ($self, %options) = @_;

    return sprintf("VIOS '%s' [system: %s] ", $options{instance_value}->{name}, $options{instance_value}->{system});
}

sub custom_errors_output {
    my ($self, %options) = @_;

    my $msg = sprintf('errors: %s', $self->{result_values}->{count});
    $msg .= ' [last: ' . $self->{result_values}->{last} . ']' if $self->{result_values}->{last} ne '';
    return $msg;
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'vios', type => COUNTER_TYPE_INSTANCE, cb_prefix_output => 'prefix_vios_output', message_multiple => 'No hardware error found on VIOS', skipped_code => { -10 => 1 } }
    ];

    $self->{maps_counters}->{vios} = [
        {
            label => 'command-status',
            type => COUNTER_KIND_TEXT,
            unknown_default => '%{status} ne "COMPLETED_OK" or %{returnCode} !~ /^0?$/',
            set => {
                key_values => [ { name => 'status' }, { name => 'returnCode' }, { name => 'message' }, { name => 'name' }, { name => 'system' } ],
                output_template => 'errlog command status: %s',
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold_ng
            }
        },
        { label => 'errors', nlabel => 'vios.errors.count', critical_default => '0', set => {
                key_values => [ { name => 'count' }, { name => 'last' } ],
                closure_custom_output => $self->can('custom_errors_output'),
                perfdatas => [
                    { template => '%s', min => 0, label_extra_instance => 1 }
                ]
            }
        }
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options, force_new_perfdata => 1);
    bless $self, $class;

    $options{options}->add_options(arguments => {
        'include-system-name:s' => { name => 'include_system_name', default => '' },
        'exclude-system-name:s' => { name => 'exclude_system_name', default => '' },
        'include-vios-name:s'   => { name => 'include_vios_name', default => '' },
        'exclude-vios-name:s'   => { name => 'exclude_vios_name', default => '' },
        'error-type:s'          => { name => 'error_type', default => 'P' },
        'error-class:s'         => { name => 'error_class', default => 'H' },
        'exclude-error:s'       => { name => 'exclude_error', default => '' },
        'retention:s'           => { name => 'retention', default => 86400 }
    });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    $self->{output}->option_exit(short_msg => 'Wrong --retention option.')
        if $self->{option_results}->{retention} !~ /^\d+$/;
}

sub manage_selection {
    my ($self, %options) = @_;

    my $since = $self->{option_results}->{retention} > 0 ? time() - $self->{option_results}->{retention} : 0;
    $self->{vios} = {};

    # 1. find running VIOS with the light LPAR quick view, then submit all CLIRunner jobs at once
    my @jobs;
    foreach my $system (@{$options{custom}->get_managed_systems()}) {
        next if is_excluded($system->{name}, $self->{option_results}->{include_system_name}, $self->{option_results}->{exclude_system_name}, output => $self->{output});
        next if $system->{state} !~ /^operating$/i;

        foreach my $vios (@{$options{custom}->get_lpars(system_uuid => $system->{uuid})}) {
            next if !defined($vios->{type}) || $vios->{type} !~ /Virtual\s*IO\s*Server/i;
            next if is_excluded($vios->{name}, $self->{option_results}->{include_vios_name}, $self->{option_results}->{exclude_vios_name}, output => $self->{output});
            if ($vios->{state} !~ /^running$/i) {
                $self->{output}->output_add(long_msg => "skipping VIOS '$vios->{name}': not running", debug => 1);
                next;
            }

            # the VIOS error log is read through the HMC CLI (viosvrcmd) run by the CLIRunner REST job
            my $job_id = $options{custom}->submit_cli_job(
                command => sprintf('viosvrcmd -m "%s" -p "%s" -c "errlog"', $system->{name}, $vios->{name})
            );
            push @jobs, { system => $system->{name}, vios => $vios->{name}, job_id => $job_id };
        }
    }

    # 2. wait for all jobs (they run in parallel on the HMC)
    my $results = $options{custom}->wait_cli_jobs(job_ids => [ grep { defined($_) && $_ ne '' } map { $_->{job_id} } @jobs ]);

    # 3. parse each VIOS error log
    foreach my $job (@jobs) {
        my $result = defined($job->{job_id}) && defined($results->{ $job->{job_id} }) ? $results->{ $job->{job_id} } :
            { status => 'FAILED', rc => '', output => 'cannot find JobID in CLIRunner response' };
        my ($system_name, $vios_name) = ($job->{system}, $job->{vios});
        my $instance = $system_name . '~' . $vios_name;
        my @lines = split(/\n/, defined($result->{output}) ? $result->{output} : '');
        $self->{vios}->{$instance} = {
            name => $vios_name,
            system => $system_name,
            status => $result->{status},
            returnCode => $result->{rc},
            message => @lines ? $lines[-1] : '',
            count => 0,
            last => ''
        };
        next if $result->{status} ne 'COMPLETED_OK' || $result->{rc} !~ /^0?$/;

        # errlog summary line: IDENTIFIER TIMESTAMP(MMDDhhmmYY) T C RESOURCE_NAME DESCRIPTION
        my $last_time = 0;
        foreach my $line (@lines) {
            next if $line !~ /^\s*([0-9A-Fa-f]{8})\s+(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s+(\S)\s+(\S)\s+(\S+)\s+(.*?)\s*$/;
            my ($identifier, $month, $day, $hour, $min, $year, $type, $class, $resource, $description) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);

            next if $self->{option_results}->{error_type} ne '' && $type !~ /^[$self->{option_results}->{error_type}]$/i;
            next if $self->{option_results}->{error_class} ne '' && $class !~ /^[$self->{option_results}->{error_class}]$/i;
            next if $self->{option_results}->{exclude_error} ne '' && $line =~ /$self->{option_results}->{exclude_error}/;

            my $timestamp = eval { timelocal(0, $min, $hour, $day, $month - 1, 2000 + $year) };
            next if $since > 0 && defined($timestamp) && $timestamp < $since;

            my $date = defined($timestamp) ? strftime('%Y-%m-%d %H:%M', localtime($timestamp)) : "$month/$day/$year $hour:$min";
            $self->{output}->output_add(
                long_msg => sprintf("    VIOS '%s' [system: %s] %s %s %s/%s %s: %s", $vios_name, $system_name, $date, $identifier, $type, $class, $resource, $description)
            );
            $self->{vios}->{$instance}->{count}++;
            if (defined($timestamp) && $timestamp >= $last_time) {
                $last_time = $timestamp;
                $self->{vios}->{$instance}->{last} = "$date $resource $description";
            }
        }
    }

    $self->{output}->option_exit(short_msg => 'No running VIOS found.')
        if !%{$self->{vios}};
}

1;

__END__

=head1 MODE

Check Virtual I/O Servers (VIOS) error log (C<errlog>), by default only permanent hardware errors.

The error log is read through the HMC CLI command C<viosvrcmd>, run by the C<CLIRunner> job of the HMC REST API
(one job per VIOS, all jobs run in parallel on the HMC):
the HMC user needs the permission to run C<viosvrcmd> (C<hmcviewer> role is not enough) and the VIOS RMC connection must be active.

=over 8

=item B<--include-system-name>

Filter managed systems by name (can be a regexp).

=item B<--exclude-system-name>

Exclude managed systems by name (can be a regexp).

=item B<--include-vios-name>

Filter VIOS by name (can be a regexp).

=item B<--exclude-vios-name>

Exclude VIOS by name (can be a regexp).

=item B<--error-type>

Error types to keep (default: C<P> for permanent). Example: C<PT> for permanent and temporary errors.
Set an empty value to keep all types.

=item B<--error-class>

Error classes to keep (default: C<H> for hardware). Example: C<HS> for hardware and software errors.
Set an empty value to keep all classes.

=item B<--exclude-error>

Exclude error log lines (can be a regexp on the whole line: identifier, resource name, description...).

=item B<--retention>

Only keep errors that occurred during the last X seconds (default: C<86400>). Set C<0> to keep all errors.

=item B<--unknown-command-status>

Define the conditions to match for the status to be UNKNOWN (default: C<%{status} ne "COMPLETED_OK" or %{returnCode} !~ /^0?$/>).
You can use the following variables: C<%{status}>, C<%{returnCode}>, C<%{message}>, C<%{name}>, C<%{system}>

=item B<--warning-command-status>

Define the conditions to match for the status to be WARNING.
You can use the following variables: C<%{status}>, C<%{returnCode}>, C<%{message}>, C<%{name}>, C<%{system}>

=item B<--critical-command-status>

Define the conditions to match for the status to be CRITICAL.
You can use the following variables: C<%{status}>, C<%{returnCode}>, C<%{message}>, C<%{name}>, C<%{system}>

=item B<--warning-errors>

Threshold on the number of errors.

=item B<--critical-errors>

Threshold on the number of errors (default: C<0>).

=back

=cut
