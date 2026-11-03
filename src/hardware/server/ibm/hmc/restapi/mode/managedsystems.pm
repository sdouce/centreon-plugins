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

package hardware::server::ibm::hmc::restapi::mode::managedsystems;

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

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'global', type => COUNTER_TYPE_GLOBAL, prefix_output => 'Number of managed systems ' },
        { name => 'systems', type => COUNTER_TYPE_INSTANCE, cb_prefix_output => 'prefix_system_output', message_multiple => 'All managed systems are ok' }
    ];

    $self->{maps_counters}->{global} = [
        { label => 'systems-detected', nlabel => 'managedsystems.detected.count', unknown_default => '@0', set => {
                key_values => [ { name => 'detected' } ],
                output_template => 'detected: %s',
                perfdatas => [
                    { template => '%s', min => 0 }
                ]
            }
        }
    ];

    $self->{maps_counters}->{systems} = [
        {
            label => 'system-status',
            type => COUNTER_KIND_TEXT,
            critical_default => '%{state} !~ /^(?:operating|standby)$/i',
            set => {
                key_values => [ { name => 'state' }, { name => 'name' }, { name => 'model' }, { name => 'serial' } ],
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
        'exclude-system-name:s' => { name => 'exclude_system_name', default => '' }
    });

    return $self;
}

sub manage_selection {
    my ($self, %options) = @_;

    $self->{global} = { detected => 0 };
    $self->{systems} = {};
    foreach my $system (@{$options{custom}->get_managed_systems()}) {
        next if is_excluded($system->{name}, $self->{option_results}->{include_system_name}, $self->{option_results}->{exclude_system_name}, output => $self->{output});

        $self->{systems}->{ $system->{uuid} } = {
            name => $system->{name},
            state => $system->{state},
            model => (defined($system->{machine_type}) ? $system->{machine_type} : '') . '-' . (defined($system->{model}) ? $system->{model} : ''),
            serial => defined($system->{serial}) ? $system->{serial} : ''
        };
        $self->{global}->{detected}++;
    }
}

1;

__END__

=head1 MODE

Check managed systems (IBM Power servers) state.

=over 8

=item B<--include-system-name>

Filter managed systems by name (can be a regexp).

=item B<--exclude-system-name>

Exclude managed systems by name (can be a regexp).

=item B<--warning-systems-detected>

Threshold.

=item B<--critical-systems-detected>

Threshold.

=item B<--unknown-system-status>

Define the conditions to match for the status to be UNKNOWN.
You can use the following variables: C<%{state}>, C<%{name}>, C<%{model}>, C<%{serial}>

=item B<--warning-system-status>

Define the conditions to match for the status to be WARNING.
You can use the following variables: C<%{state}>, C<%{name}>, C<%{model}>, C<%{serial}>

=item B<--critical-system-status>

Define the conditions to match for the status to be CRITICAL (default: C<%{state} !~ /^(?:operating|standby)$/i>).
You can use the following variables: C<%{state}>, C<%{name}>, C<%{model}>, C<%{serial}>

=back

=cut
