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

package hardware::server::ibm::hmc::restapi::mode::vios;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::misc qw/is_excluded/;
use centreon::plugins::constants qw(:counters);
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold_ng);

sub prefix_system_output {
    my ($self, %options) = @_;

    return "managed system '" . $options{instance_value}->{name} . "' ";
}

sub system_long_output {
    my ($self, %options) = @_;

    return "checking managed system '" . $options{instance_value}->{name} . "'";
}

sub prefix_vios_output {
    my ($self, %options) = @_;

    return "VIOS '" . $options{instance_value}->{name} . "' ";
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        {
            name => 'systems', type => COUNTER_TYPE_MULTIPLE, cb_prefix_output => 'prefix_system_output', cb_long_output => 'system_long_output',
            message_multiple => 'All VIOS are ok', indent_long_output => '    ',
            group => [
                { name => 'global', type => COUNTER_MULTIPLE_INSTANCE, skipped_code => { -10 => 1 } },
                { name => 'vios', type => COUNTER_MULTIPLE_SUBINSTANCE, display_long => 1, cb_prefix_output => 'prefix_vios_output', message_multiple => 'all VIOS are ok', skipped_code => { -10 => 1 } }
            ]
        }
    ];

    $self->{maps_counters}->{global} = [
        { label => 'vios-running', nlabel => 'vios.running.count', critical_default => '2:', set => {
                key_values => [ { name => 'running' }, { name => 'detected' } ],
                output_template => 'VIOS running: %s',
                perfdatas => [
                    { template => '%s', min => 0, max => 'detected', label_extra_instance => 1 }
                ]
            }
        }
    ];

    $self->{maps_counters}->{vios} = [
        {
            label => 'vios-status',
            type => COUNTER_KIND_TEXT,
            critical_default => '%{state} !~ /^running$/i',
            set => {
                key_values => [ { name => 'state' }, { name => 'name' }, { name => 'system' }, { name => 'referenceCode' }, { name => 'osVersion' } ],
                output_template => 'state: %s',
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold_ng
            }
        },
        {
            label => 'vios-rmc-status',
            type => COUNTER_KIND_TEXT,
            warning_default => '%{state} =~ /^running$/i and %{rmcState} !~ /^active$/i',
            set => {
                key_values => [ { name => 'rmcState' }, { name => 'state' }, { name => 'name' }, { name => 'system' } ],
                output_template => 'RMC state: %s',
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
        'exclude-vios-name:s'   => { name => 'exclude_vios_name', default => '' }
    });

    return $self;
}

sub manage_selection {
    my ($self, %options) = @_;

    $self->{systems} = {};
    foreach my $system (@{$options{custom}->get_managed_systems()}) {
        next if is_excluded($system->{name}, $self->{option_results}->{include_system_name}, $self->{option_results}->{exclude_system_name}, output => $self->{output});

        my $entry = { name => $system->{name}, global => { detected => 0, running => 0 }, vios => {} };
        foreach my $vios (@{$options{custom}->get_vios(system_uuid => $system->{uuid})}) {
            next if is_excluded($vios->{name}, $self->{option_results}->{include_vios_name}, $self->{option_results}->{exclude_vios_name}, output => $self->{output});

            $entry->{vios}->{ $vios->{name} } = {
                name => $vios->{name},
                system => $system->{name},
                state => $vios->{state},
                rmcState => $vios->{rmc_state},
                referenceCode => $vios->{reference_code},
                osVersion => $vios->{os_version}
            };
            $entry->{global}->{detected}++;
            $entry->{global}->{running}++ if $vios->{state} =~ /^running$/i;
        }

        # managed systems without VIOS are not monitored
        next if $entry->{global}->{detected} == 0;
        $self->{systems}->{ $system->{name} } = $entry;
    }

    $self->{output}->option_exit(short_msg => 'No VIOS found.')
        if !%{$self->{systems}};
}

1;

__END__

=head1 MODE

Check Virtual I/O Servers (VIOS) state, RMC connection and number of running VIOS per managed system.

=over 8

=item B<--include-system-name>

Filter managed systems by name (can be a regexp).

=item B<--exclude-system-name>

Exclude managed systems by name (can be a regexp).

=item B<--include-vios-name>

Filter VIOS by name (can be a regexp).

=item B<--exclude-vios-name>

Exclude VIOS by name (can be a regexp).

=item B<--warning-vios-running>

Threshold on the number of running VIOS per managed system.

=item B<--critical-vios-running>

Threshold on the number of running VIOS per managed system (default: C<2:>).

=item B<--unknown-vios-status>

Define the conditions to match for the status to be UNKNOWN.
You can use the following variables: C<%{state}>, C<%{name}>, C<%{system}>, C<%{referenceCode}>, C<%{osVersion}>

=item B<--warning-vios-status>

Define the conditions to match for the status to be WARNING.
You can use the following variables: C<%{state}>, C<%{name}>, C<%{system}>, C<%{referenceCode}>, C<%{osVersion}>

=item B<--critical-vios-status>

Define the conditions to match for the status to be CRITICAL (default: C<%{state} !~ /^running$/i>).
You can use the following variables: C<%{state}>, C<%{name}>, C<%{system}>, C<%{referenceCode}>, C<%{osVersion}>

=item B<--unknown-vios-rmc-status>

Define the conditions to match for the status to be UNKNOWN.
You can use the following variables: C<%{rmcState}>, C<%{state}>, C<%{name}>, C<%{system}>

=item B<--warning-vios-rmc-status>

Define the conditions to match for the status to be WARNING (default: C<%{state} =~ /^running$/i and %{rmcState} !~ /^active$/i>).
You can use the following variables: C<%{rmcState}>, C<%{state}>, C<%{name}>, C<%{system}>

=item B<--critical-vios-rmc-status>

Define the conditions to match for the status to be CRITICAL.
You can use the following variables: C<%{rmcState}>, C<%{state}>, C<%{name}>, C<%{system}>

=back

=cut
