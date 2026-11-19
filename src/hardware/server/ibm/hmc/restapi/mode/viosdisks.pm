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

package hardware::server::ibm::hmc::restapi::mode::viosdisks;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::misc qw/is_excluded/;
use centreon::plugins::constants qw(:counters);
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold_ng);

sub prefix_vios_output {
    my ($self, %options) = @_;

    return sprintf("VIOS '%s' [system: %s] ", $options{instance_value}->{name}, $options{instance_value}->{system});
}

sub vios_long_output {
    my ($self, %options) = @_;

    return sprintf("checking VIOS '%s' [system: %s]", $options{instance_value}->{name}, $options{instance_value}->{system});
}

sub prefix_disk_output {
    my ($self, %options) = @_;

    return "disk '" . $options{instance_value}->{name} . "' ";
}

sub custom_command_output {
    my ($self, %options) = @_;

    my $msg = 'pdisks command status: ' . $self->{result_values}->{status};
    if ($self->{result_values}->{status} ne 'COMPLETED_OK' || $self->{result_values}->{returnCode} !~ /^0?$/) {
        $msg .= ' [rc: ' . $self->{result_values}->{returnCode} . ']' if $self->{result_values}->{returnCode} ne '';
        $msg .= ' [message: ' . $self->{result_values}->{message} . ']' if $self->{result_values}->{message} ne '';
    }
    return $msg;
}

sub prefix_pdisk_output {
    my ($self, %options) = @_;

    return "pdisk '" . $options{instance_value}->{name} . "' ";
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        {
            name => 'vios', type => COUNTER_TYPE_MULTIPLE, cb_prefix_output => 'prefix_vios_output', cb_long_output => 'vios_long_output',
            message_multiple => 'All VIOS disks are ok', indent_long_output => '    ',
            group => [
                { name => 'global', type => COUNTER_MULTIPLE_INSTANCE, skipped_code => { -10 => 1 } },
                { name => 'disks', type => COUNTER_MULTIPLE_SUBINSTANCE, display_long => 1, cb_prefix_output => 'prefix_disk_output', message_multiple => 'all disks are ok', skipped_code => { -10 => 1 } },
                { name => 'pdisks', type => COUNTER_MULTIPLE_SUBINSTANCE, display_long => 1, cb_prefix_output => 'prefix_pdisk_output', message_multiple => 'all pdisks are ok', skipped_code => { -10 => 1 } }
            ]
        }
    ];

    $self->{maps_counters}->{global} = [
        {
            label => 'pdisks-command-status',
            type => COUNTER_KIND_TEXT,
            unknown_default => '%{status} ne "COMPLETED_OK" or %{returnCode} !~ /^0?$/',
            set => {
                key_values => [ { name => 'status' }, { name => 'returnCode' }, { name => 'message' }, { name => 'name' }, { name => 'system' } ],
                closure_custom_output => $self->can('custom_command_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold_ng
            }
        },
        { label => 'disks-detected', nlabel => 'vios.disks.detected.count', set => {
                key_values => [ { name => 'detected' } ],
                output_template => 'disks detected: %s',
                perfdatas => [
                    { template => '%s', min => 0, label_extra_instance => 1 }
                ]
            }
        },
        { label => 'disks-failed', nlabel => 'vios.disks.failed.count', set => {
                key_values => [ { name => 'failed' }, { name => 'detected' } ],
                output_template => 'disks failed: %s',
                perfdatas => [
                    { template => '%s', min => 0, max => 'detected', label_extra_instance => 1 }
                ]
            }
        },
        { label => 'pdisks-detected', nlabel => 'vios.pdisks.detected.count', set => {
                key_values => [ { name => 'pdisks_detected' } ],
                output_template => 'pdisks detected: %s',
                perfdatas => [
                    { template => '%s', min => 0, label_extra_instance => 1 }
                ]
            }
        },
        { label => 'pdisks-failed', nlabel => 'vios.pdisks.failed.count', set => {
                key_values => [ { name => 'pdisks_failed' }, { name => 'pdisks_detected' } ],
                output_template => 'pdisks failed: %s',
                perfdatas => [
                    { template => '%s', min => 0, max => 'pdisks_detected', label_extra_instance => 1 }
                ]
            }
        }
    ];

    $self->{maps_counters}->{disks} = [
        {
            label => 'disk-status',
            type => COUNTER_KIND_TEXT,
            critical_default => '%{state} ne "" and %{state} !~ /^active$/i',
            set => {
                key_values => [ { name => 'state' }, { name => 'name' }, { name => 'vios' }, { name => 'system' }, { name => 'description' } ],
                output_template => 'state: %s',
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold_ng
            }
        }
    ];

    $self->{maps_counters}->{pdisks} = [
        {
            label => 'pdisk-status',
            type => COUNTER_KIND_TEXT,
            critical_default => '%{state} !~ /^available$/i',
            set => {
                key_values => [ { name => 'state' }, { name => 'name' }, { name => 'description' }, { name => 'vios' }, { name => 'system' } ],
                output_template => 'state: %s',
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold_ng
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
        'include-disk-name:s'   => { name => 'include_disk_name', default => '' },
        'exclude-disk-name:s'   => { name => 'exclude_disk_name', default => '' },
        'include-pdisk-name:s'  => { name => 'include_pdisk_name', default => '' },
        'exclude-pdisk-name:s'  => { name => 'exclude_pdisk_name', default => '' },
        'skip-pdisks'           => { name => 'skip_pdisks' },
        'vios-group:s'          => { name => 'vios_group', default => 'ViosStorage' }
    });

    return $self;
}

sub job_result {
    my ($self, %options) = @_;

    return defined($options{job_id}) && defined($options{results}->{ $options{job_id} }) ? $options{results}->{ $options{job_id} } :
        { status => 'FAILED', rc => '', output => 'cannot find JobID in CLIRunner response' };
}

sub set_command_status {
    my ($self, %options) = @_;

    my @lines = split(/\n/, defined($options{result}->{output}) ? $options{result}->{output} : '');
    $options{entry}->{global}->{$_->[0]} = $_->[1] foreach (
        [ name => $options{entry}->{name} ], [ system => $options{entry}->{system} ],
        [ status => $options{result}->{status} ], [ returnCode => $options{result}->{rc} ], [ message => @lines ? $lines[-1] : '' ]
    );
    my $ok = ($options{result}->{status} eq 'COMPLETED_OK' && $options{result}->{rc} =~ /^0?$/) ? 1 : 0;
    $options{entry}->{global}->{message} = join(' ', grep { /\S/ } @lines) if !$ok;
    return $ok ? \@lines : undef;
}

# pdisks (physical disks behind a SAS RAID adapter) are not exposed by the REST API objects: they are listed
# with the VIOS command lsdev (padmin, no root access), run through the HMC CLI command viosvrcmd by the
# CLIRunner REST job (one job per VIOS, all jobs run in parallel on the HMC).
sub add_pdisks {
    my ($self, %options) = @_;

    my %jobs;
    foreach my $key (keys %{$self->{vios}}) {
        $jobs{$key} = $options{custom}->submit_cli_job(
            command => sprintf('viosvrcmd -m "%s" -p "%s" -c "lsdev"', $self->{vios}->{$key}->{system}, $self->{vios}->{$key}->{name})
        );
    }
    my $results = $options{custom}->wait_cli_jobs(job_ids => [ grep { defined($_) && $_ ne '' } values %jobs ]);

    foreach my $key (keys %jobs) {
        my $entry = $self->{vios}->{$key};
        my $lines = $self->set_command_status(entry => $entry, result => $self->job_result(job_id => $jobs{$key}, results => $results));
        next if !defined($lines);

        # lsdev output: name status description
        foreach my $line (@$lines) {
            next if $line !~ /^\s*(pdisk\d+)\s+(\S+)\s*(.*?)\s*$/;
            my ($name, $state, $description) = ($1, $2, $3);
            next if is_excluded($name, $self->{option_results}->{include_pdisk_name}, $self->{option_results}->{exclude_pdisk_name}, output => $self->{output});

            $entry->{pdisks}->{$name} = { name => $name, state => $state, description => $description, vios => $entry->{name}, system => $entry->{system} };
            $entry->{global}->{pdisks_detected}++;
            $entry->{global}->{pdisks_failed}++ if $state !~ /^available$/i;
        }
        if (%{$entry->{pdisks}}) {
            $entry->{global}->{pdisks_failed} = 0 if !defined($entry->{global}->{pdisks_failed});
        } else {
            # VIOS without pdisk (no SAS RAID adapter): only hdisks are checked
            delete $entry->{global}->{$_} foreach ('status', 'returnCode', 'message');
        }
    }
}

sub manage_selection {
    my ($self, %options) = @_;

    $self->{vios} = {};
    foreach my $system (@{$options{custom}->get_managed_systems()}) {
        next if is_excluded($system->{name}, $self->{option_results}->{include_system_name}, $self->{option_results}->{exclude_system_name}, output => $self->{output});

        foreach my $vios (@{$options{custom}->get_vios(system_uuid => $system->{uuid}, group => $self->{option_results}->{vios_group})}) {
            next if is_excluded($vios->{name}, $self->{option_results}->{include_vios_name}, $self->{option_results}->{exclude_vios_name}, output => $self->{output});
            if ($vios->{state} !~ /^running$/i) {
                $self->{output}->output_add(long_msg => "skipping VIOS '$vios->{name}': not running", debug => 1);
                next;
            }

            my $entry = { name => $vios->{name}, system => $system->{name}, global => { detected => 0, failed => 0 }, disks => {}, pdisks => {} };
            foreach my $disk (@{$vios->{disks}}) {
                next if is_excluded($disk->{name}, $self->{option_results}->{include_disk_name}, $self->{option_results}->{exclude_disk_name}, output => $self->{output});

                $entry->{disks}->{ $disk->{name} } = {
                    name => $disk->{name},
                    vios => $vios->{name},
                    system => $system->{name},
                    state => $disk->{state},
                    description => $disk->{description}
                };
                $entry->{global}->{detected}++;
                $entry->{global}->{failed}++ if $disk->{state} ne '' && $disk->{state} !~ /^active$/i;
            }
            $self->{vios}->{ $system->{name} . '~' . $vios->{name} } = $entry;
        }
    }

    $self->add_pdisks(custom => $options{custom}) if !defined($self->{option_results}->{skip_pdisks}) && %{$self->{vios}};

    $self->{output}->option_exit(short_msg => 'No running VIOS found.')
        if !%{$self->{vios}};
}

1;

__END__

=head1 MODE

Check physical volumes (hdisks) state seen by each running Virtual I/O Server (VIOS) and,
on VIOS with internal SAS RAID adapters, the physical disks (pdisks) state.

The hdisks state comes from the HMC REST API. The pdisks are listed with the VIOS command C<lsdev>
(padmin, no root access needed), run through the HMC CLI command C<viosvrcmd> by the C<CLIRunner> job
of the HMC REST API (one job per VIOS, all jobs run in parallel on the HMC): the HMC user needs the permission
to run C<viosvrcmd> and the VIOS RMC connection must be active.
The pdisk state is the device state (C<Available>, C<Defined>...), not the RAID array state:
RAID array and pdisk failures are reported in the VIOS error log (see the C<vios-errors> mode).
VIOS without pdisk only report their hdisks. Use C<--skip-pdisks> to only use the REST API.

=over 8

=item B<--include-system-name>

Filter managed systems by name (can be a regexp).

=item B<--exclude-system-name>

Exclude managed systems by name (can be a regexp).

=item B<--include-vios-name>

Filter VIOS by name (can be a regexp).

=item B<--exclude-vios-name>

Exclude VIOS by name (can be a regexp).

=item B<--include-disk-name>

Filter disks by name (can be a regexp).

=item B<--exclude-disk-name>

Exclude disks by name (can be a regexp).

=item B<--include-pdisk-name>

Filter pdisks by name (can be a regexp).

=item B<--exclude-pdisk-name>

Exclude pdisks by name (can be a regexp).

=item B<--skip-pdisks>

Do not check pdisks (no CLIRunner job).

=item B<--vios-group>

Extended group(s) requested to the HMC to get storage details (default: C<ViosStorage>).
Set an empty value to use the HMC default.

=item B<--warning-disks-detected>

Threshold.

=item B<--critical-disks-detected>

Threshold.

=item B<--warning-disks-failed>

Threshold.

=item B<--critical-disks-failed>

Threshold.

=item B<--warning-pdisks-detected>

Threshold.

=item B<--critical-pdisks-detected>

Threshold.

=item B<--warning-pdisks-failed>

Threshold on the number of pdisks not available.

=item B<--critical-pdisks-failed>

Threshold on the number of pdisks not available.

=item B<--unknown-pdisks-command-status>

Define the conditions to match for the status to be UNKNOWN (default: C<%{status} ne "COMPLETED_OK" or %{returnCode} !~ /^0?$/>).
You can use the following variables: C<%{status}>, C<%{returnCode}>, C<%{message}>, C<%{name}>, C<%{system}>

=item B<--warning-pdisks-command-status>

Define the conditions to match for the status to be WARNING.
You can use the following variables: C<%{status}>, C<%{returnCode}>, C<%{message}>, C<%{name}>, C<%{system}>

=item B<--critical-pdisks-command-status>

Define the conditions to match for the status to be CRITICAL.
You can use the following variables: C<%{status}>, C<%{returnCode}>, C<%{message}>, C<%{name}>, C<%{system}>

=item B<--unknown-pdisk-status>

Define the conditions to match for the status to be UNKNOWN.
You can use the following variables: C<%{state}>, C<%{name}>, C<%{description}>, C<%{vios}>, C<%{system}>

=item B<--warning-pdisk-status>

Define the conditions to match for the status to be WARNING.
You can use the following variables: C<%{state}>, C<%{name}>, C<%{description}>, C<%{vios}>, C<%{system}>

=item B<--critical-pdisk-status>

Define the conditions to match for the status to be CRITICAL (default: C<%{state} !~ /^available$/i>).
You can use the following variables: C<%{state}>, C<%{name}>, C<%{description}>, C<%{vios}>, C<%{system}>

=item B<--unknown-disk-status>

Define the conditions to match for the status to be UNKNOWN.
You can use the following variables: C<%{state}>, C<%{name}>, C<%{vios}>, C<%{system}>, C<%{description}>

=item B<--warning-disk-status>

Define the conditions to match for the status to be WARNING.
You can use the following variables: C<%{state}>, C<%{name}>, C<%{vios}>, C<%{system}>, C<%{description}>

=item B<--critical-disk-status>

Define the conditions to match for the status to be CRITICAL (default: C<%{state} ne "" and %{state} !~ /^active$/i>).
You can use the following variables: C<%{state}>, C<%{name}>, C<%{vios}>, C<%{system}>, C<%{description}>

=back

=cut
