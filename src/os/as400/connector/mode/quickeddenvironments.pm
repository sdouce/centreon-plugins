#
# Copyright 2026 Centreon (http://www.centreon.com/)
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
package os::as400::connector::mode::quickeddenvironments;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold_ng);

sub custom_status_output {
    my ($self, %options) = @_;

    my $msg = 'status: ' . $self->{result_values}->{status};
    $msg .= ' (' . $self->{result_values}->{message} . ')'
        if (defined($self->{result_values}->{message}) && $self->{result_values}->{message} ne '');
    return $msg;
}

sub prefix_env_output {
    my ($self, %options) = @_;

    return "QuickEDD environment '" . $options{instance_value}->{name} . "' ";
}

sub prefix_global_output {
    my ($self, %options) = @_;

    return 'QuickEDD environments ';
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'global', cb_prefix_output => 'prefix_global_output', type => 0 },
        { name => 'env', type => 1, cb_prefix_output => 'prefix_env_output', message_multiple => 'All QuickEDD environments are ok', skipped_code => { -10 => 1 } }
    ];

    $self->{maps_counters}->{global} = [
        { label => 'environments-total', nlabel => 'quickedd.environments.total.count', display_ok => 0, set => {
                key_values => [ { name => 'total' } ],
                output_template => 'total: %s',
                perfdatas => [
                    { template => '%s', min => 0 }
                ]
            }
        }
    ];

    $self->{maps_counters}->{env} = [
        {
            label => 'status',
            type => 2,
            unknown_default => '%{status} =~ /error/i',
            critical_default => '%{status} =~ /^(inactive|unknown)$/i',
            set => {
                key_values => [ { name => 'status' }, { name => 'message' }, { name => 'name' } ],
                closure_custom_output => $self->can('custom_status_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold_ng
            }
        },
        { label => 'errors', nlabel => 'quickedd.environment.errors.count', set => {
                key_values => [ { name => 'errors' }, { name => 'name' } ],
                output_template => 'errors: %s',
                perfdatas => [
                    { template => '%s', min => 0, label_extra_instance => 1, instance_use => 'name' }
                ]
            }
        },
        { label => 'waiting', nlabel => 'quickedd.environment.entries.waiting.count', set => {
                key_values => [ { name => 'waiting' }, { name => 'name' } ],
                output_template => 'waiting entries: %s',
                perfdatas => [
                    { template => '%s', min => 0, label_extra_instance => 1, instance_use => 'name' }
                ]
            }
        },
        { label => 'delay', nlabel => 'quickedd.environment.delay.seconds', set => {
                key_values => [ { name => 'delay' }, { name => 'name' } ],
                output_template => 'journal delay: %s s',
                perfdatas => [
                    { template => '%s', unit => 's', min => 0, label_extra_instance => 1, instance_use => 'name' }
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
        'lib-qedd:s'     => { name => 'lib_qedd' },
        'lib-prog:s'     => { name => 'lib_prog' },
        'quickedd-env:s@'  => { name => 'quickedd_env' },
        'include-name:s' => { name => 'include_name' },
        'exclude-name:s' => { name => 'exclude_name' }
    });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    if (!defined($self->{option_results}->{lib_prog}) || $self->{option_results}->{lib_prog} eq '') {
        $self->{output}->add_option_msg(short_msg => 'Need to specify --lib-prog option (library of the PZHAWRKM service program)');
        $self->{output}->option_exit();
    }
}

sub manage_selection {
    my ($self, %options) = @_;

    my $args = { libProg => $self->{option_results}->{lib_prog}, environments => [] };
    $args->{libQedd} = $self->{option_results}->{lib_qedd}
        if (defined($self->{option_results}->{lib_qedd}) && $self->{option_results}->{lib_qedd} ne '');
    if (defined($self->{option_results}->{quickedd_env})) {
        foreach my $env (@{$self->{option_results}->{quickedd_env}}) {
            foreach (split(/,/, $env)) {
                s/^\s+|\s+$//g;
                push @{$args->{environments}}, uc($_) if ($_ ne '');
            }
        }
    }

    my $entries = $options{custom}->request_api(command => 'getQuickEddEnvironments', args => $args);

    $self->{global} = { total => 0 };
    $self->{env} = {};
    foreach my $entry (@{$entries->{result}}) {
        next if (defined($self->{option_results}->{include_name}) && $self->{option_results}->{include_name} ne '' &&
            $entry->{name} !~ /$self->{option_results}->{include_name}/);
        next if (defined($self->{option_results}->{exclude_name}) && $self->{option_results}->{exclude_name} ne '' &&
            $entry->{name} =~ /$self->{option_results}->{exclude_name}/);

        my $failed = (defined($entry->{status}) && $entry->{status} eq 'failed') ? 1 : 0;
        $self->{env}->{ $entry->{name} } = {
            name => $entry->{name},
            status => $failed ? 'error' : $entry->{active},
            message => $failed ? $entry->{message} : '',
            errors => $entry->{errors},
            waiting => $entry->{waiting},
            delay => $entry->{delay}
        };
        $self->{global}->{total}++;
    }

    if (scalar(keys %{$self->{env}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => 'No QuickEDD environment found');
        $self->{output}->option_exit();
    }
}

1;

__END__

=head1 MODE

Check QuickEDD environments (activity, errors, waiting entries and journal delay).

The connector calls the QuickEDD service program <lib-prog>/PZHAWRKM
(procedures EnvIsActive, EnvError, getEnvWait, EnvDelayJrn).

=over 8

=item B<--lib-prog>

Library of the QuickEDD service program PZHAWRKM (required). It is added to the library list.

=item B<--lib-qedd>

QuickEDD library to add to the library list.

=item B<--quickedd-env>

QuickEDD environment to check (6 characters max). Can be used multiple times or as a comma separated list.
If not set, environments are discovered with getEnvList.

=item B<--include-name>

Filter environments by name (can be a regexp).

=item B<--exclude-name>

Exclude environments by name (can be a regexp).

=item B<--unknown-status>

Define the conditions to match for the status to be UNKNOWN (default: '%{status} =~ /error/i').
You can use the following variables: %{status}, %{message}, %{name}

=item B<--warning-status>

Define the conditions to match for the status to be WARNING.
You can use the following variables: %{status}, %{message}, %{name}

=item B<--critical-status>

Define the conditions to match for the status to be CRITICAL (default: '%{status} =~ /^(inactive|unknown)$/i').
You can use the following variables: %{status}, %{message}, %{name}

=item B<--warning-*> B<--critical-*>

Thresholds.
Can be: 'environments-total', 'errors', 'waiting', 'delay' (s).

=back

=cut
