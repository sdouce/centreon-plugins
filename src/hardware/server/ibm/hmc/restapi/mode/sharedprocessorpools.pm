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

package hardware::server::ibm::hmc::restapi::mode::sharedprocessorpools;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::misc qw/is_excluded/;
use centreon::plugins::constants qw(:counters);

sub prefix_pool_output {
    my ($self, %options) = @_;

    return sprintf("shared processor pool '%s' [system: %s] ", $options{instance_value}->{name}, $options{instance_value}->{system});
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'pools', type => COUNTER_TYPE_INSTANCE, cb_prefix_output => 'prefix_pool_output', message_multiple => 'All shared processor pools are ok', skipped_code => { -10 => 1 } }
    ];

    $self->{maps_counters}->{pools} = [
        { label => 'pool-utilization', nlabel => 'pool.cpu.utilization.percentage', set => {
                key_values => [ { name => 'prct_used' }, { name => 'used' }, { name => 'size' } ],
                output_template => 'usage: %.2f %%',
                perfdatas => [
                    { template => '%.2f', unit => '%', min => 0, max => 100, label_extra_instance => 1 }
                ]
            }
        },
        { label => 'pool-utilized', nlabel => 'pool.cpu.utilized.count', display_ok => 0, set => {
                key_values => [ { name => 'used' }, { name => 'size' } ],
                output_template => 'processor units used: %.2f',
                perfdatas => [
                    { template => '%.3f', min => 0, max => 'size', label_extra_instance => 1 }
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
        'include-pool-name:s'   => { name => 'include_pool_name', default => '' },
        'exclude-pool-name:s'   => { name => 'exclude_pool_name', default => '' }
    });

    return $self;
}

sub first_value {
    my ($value) = @_;

    return ref($value) eq 'ARRAY' ? $value->[0] : $value;
}

sub manage_selection {
    my ($self, %options) = @_;

    $self->{pools} = {};
    foreach my $system (@{$options{custom}->get_managed_systems()}) {
        next if is_excluded($system->{name}, $self->{option_results}->{include_system_name}, $self->{option_results}->{exclude_system_name}, output => $self->{output});

        my $metrics = $options{custom}->get_processed_metrics(system_uuid => $system->{uuid});
        my $util = ref($metrics) eq 'HASH' ? $metrics->{systemUtil}->{utilSamples}->[0]->{serverUtil} : undef;
        if (!defined($util)) {
            $self->{output}->output_add(long_msg => "skipping managed system '$system->{name}': no performance data (is PCM data collection enabled?)", debug => 1);
            next;
        }

        foreach my $pool (ref($util->{sharedProcessorPool}) eq 'ARRAY' ? @{$util->{sharedProcessorPool}} : ()) {
            my $name = defined($pool->{name}) ? $pool->{name} : 'pool' . $pool->{id};
            next if is_excluded($name, $self->{option_results}->{include_pool_name}, $self->{option_results}->{exclude_pool_name}, output => $self->{output});

            my $size = first_value($pool->{assignedProcUnits});
            $size = first_value($pool->{configuredProcUnits}) if !defined($size) || $size == 0;
            my $used = first_value($pool->{utilizedProcUnits});
            next if !defined($size) || $size == 0 || !defined($used);

            $self->{pools}->{ $system->{name} . '~' . $name } = {
                name => $name,
                system => $system->{name},
                size => $size,
                used => $used,
                prct_used => $used * 100 / $size
            };
        }
    }

    $self->{output}->option_exit(short_msg => 'No shared processor pool found (check filters and that PCM data collection is enabled).')
        if !%{$self->{pools}};
}

1;

__END__

=head1 MODE

Check shared processor pools usage (Performance and Capacity Monitoring processed metrics).
PCM data collection must be enabled on the managed systems.

=over 8

=item B<--include-system-name>

Filter managed systems by name (can be a regexp).

=item B<--exclude-system-name>

Exclude managed systems by name (can be a regexp).

=item B<--include-pool-name>

Filter shared processor pools by name (can be a regexp).

=item B<--exclude-pool-name>

Exclude shared processor pools by name (can be a regexp).

=item B<--warning-*> B<--critical-*>

Thresholds.
Can be: 'pool-utilization' (%), 'pool-utilized' (processor units).

=back

=cut
