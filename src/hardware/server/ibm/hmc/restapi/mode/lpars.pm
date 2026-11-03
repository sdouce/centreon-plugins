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

package hardware::server::ibm::hmc::restapi::mode::lpars;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::misc qw/is_excluded/;
use centreon::plugins::constants qw(:counters);
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold_ng);

sub prefix_lpar_output {
    my ($self, %options) = @_;

    return sprintf("partition '%s' [system: %s] ", $options{instance_value}->{name}, $options{instance_value}->{system});
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'global', type => COUNTER_TYPE_GLOBAL, prefix_output => 'Number of partitions ' },
        { name => 'lpars', type => COUNTER_TYPE_INSTANCE, cb_prefix_output => 'prefix_lpar_output', message_multiple => 'All partitions are ok', skipped_code => { -10 => 1 } }
    ];

    $self->{maps_counters}->{global} = [
        { label => 'lpars-detected', nlabel => 'lpars.detected.count', unknown_default => '@0', set => {
                key_values => [ { name => 'detected' } ],
                output_template => 'detected: %s',
                perfdatas => [
                    { template => '%s', min => 0 }
                ]
            }
        },
        { label => 'lpars-running', nlabel => 'lpars.running.count', set => {
                key_values => [ { name => 'running' }, { name => 'detected' } ],
                output_template => 'running: %s',
                perfdatas => [
                    { template => '%s', min => 0, max => 'detected' }
                ]
            }
        }
    ];

    $self->{maps_counters}->{lpars} = [
        {
            label => 'lpar-status',
            type => COUNTER_KIND_TEXT,
            critical_default => '%{state} =~ /error|failed|not available/i',
            set => {
                key_values => [
                    { name => 'state' }, { name => 'rmcState' }, { name => 'referenceCode' },
                    { name => 'name' }, { name => 'system' }, { name => 'type' }
                ],
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
        'include-lpar-name:s'   => { name => 'include_lpar_name', default => '' },
        'exclude-lpar-name:s'   => { name => 'exclude_lpar_name', default => '' },
        'include-lpar-type:s'   => { name => 'include_lpar_type', default => '' },
        'exclude-lpar-type:s'   => { name => 'exclude_lpar_type', default => '' }
    });

    return $self;
}

sub manage_selection {
    my ($self, %options) = @_;

    $self->{global} = { detected => 0, running => 0 };
    $self->{lpars} = {};
    foreach my $system (@{$options{custom}->get_managed_systems()}) {
        next if is_excluded($system->{name}, $self->{option_results}->{include_system_name}, $self->{option_results}->{exclude_system_name}, output => $self->{output});

        foreach my $lpar (@{$options{custom}->get_lpars(system_uuid => $system->{uuid})}) {
            next if is_excluded($lpar->{name}, $self->{option_results}->{include_lpar_name}, $self->{option_results}->{exclude_lpar_name}, output => $self->{output})
                || is_excluded(defined($lpar->{type}) ? $lpar->{type} : '', $self->{option_results}->{include_lpar_type}, $self->{option_results}->{exclude_lpar_type}, output => $self->{output});

            $self->{lpars}->{ $system->{name} . '~' . $lpar->{name} } = {
                name => $lpar->{name},
                system => $system->{name},
                type => defined($lpar->{type}) ? $lpar->{type} : '',
                state => $lpar->{state},
                rmcState => $lpar->{rmc_state},
                referenceCode => $lpar->{reference_code}
            };
            $self->{global}->{detected}++;
            $self->{global}->{running}++ if $lpar->{state} =~ /^running$/i;
        }
    }
}

1;

__END__

=head1 MODE

Check logical partitions (LPAR) state.

=over 8

=item B<--include-system-name>

Filter managed systems by name (can be a regexp).

=item B<--exclude-system-name>

Exclude managed systems by name (can be a regexp).

=item B<--include-lpar-name>

Filter partitions by name (can be a regexp).

=item B<--exclude-lpar-name>

Exclude partitions by name (can be a regexp).

=item B<--include-lpar-type>

Filter partitions by type (can be a regexp). Example: C<AIX/Linux>, C<Virtual IO Server>, C<OS400>.

=item B<--exclude-lpar-type>

Exclude partitions by type (can be a regexp).

=item B<--warning-lpars-detected>

Threshold.

=item B<--critical-lpars-detected>

Threshold.

=item B<--warning-lpars-running>

Threshold.

=item B<--critical-lpars-running>

Threshold.

=item B<--unknown-lpar-status>

Define the conditions to match for the status to be UNKNOWN.
You can use the following variables: C<%{state}>, C<%{rmcState}>, C<%{referenceCode}>, C<%{name}>, C<%{system}>, C<%{type}>

=item B<--warning-lpar-status>

Define the conditions to match for the status to be WARNING.
You can use the following variables: C<%{state}>, C<%{rmcState}>, C<%{referenceCode}>, C<%{name}>, C<%{system}>, C<%{type}>

=item B<--critical-lpar-status>

Define the conditions to match for the status to be CRITICAL (default: C<%{state} =~ /error|failed|not available/i>).
You can use the following variables: C<%{state}>, C<%{rmcState}>, C<%{referenceCode}>, C<%{name}>, C<%{system}>, C<%{type}>

=back

=cut
