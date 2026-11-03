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

package hardware::server::ibm::hmc::restapi::mode::systemusage;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::misc qw/is_excluded/;
use centreon::plugins::constants qw(:counters);

sub prefix_system_output {
    my ($self, %options) = @_;

    return "managed system '" . $options{instance_value}->{name} . "' ";
}

sub custom_memory_output {
    my ($self, %options) = @_;

    my ($total_value, $total_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{total});
    my ($assigned_value, $assigned_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{assigned});
    my ($free_value, $free_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{free});
    return sprintf(
        'memory total: %s assigned to partitions: %s (%.2f%%) available: %s (%.2f%%)',
        $total_value . ' ' . $total_unit,
        $assigned_value . ' ' . $assigned_unit, $self->{result_values}->{prct_assigned},
        $free_value . ' ' . $free_unit, $self->{result_values}->{prct_free}
    );
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'systems', type => COUNTER_TYPE_INSTANCE, cb_prefix_output => 'prefix_system_output', message_multiple => 'All managed systems usages are ok', skipped_code => { -10 => 1 } }
    ];

    $self->{maps_counters}->{systems} = [
        { label => 'cpu-utilization', nlabel => 'system.cpu.utilization.percentage', set => {
                key_values => [ { name => 'cpu_prct' }, { name => 'cpu_used' }, { name => 'cpu_total' } ],
                output_template => 'cpu usage: %.2f %%',
                perfdatas => [
                    { template => '%.2f', unit => '%', min => 0, max => 100, label_extra_instance => 1 }
                ]
            }
        },
        { label => 'cpu-utilized', nlabel => 'system.cpu.utilized.count', display_ok => 0, set => {
                key_values => [ { name => 'cpu_used' }, { name => 'cpu_total' } ],
                output_template => 'processor units used: %.2f',
                perfdatas => [
                    { template => '%.3f', min => 0, max => 'cpu_total', label_extra_instance => 1 }
                ]
            }
        },
        { label => 'memory-assigned', nlabel => 'system.memory.assigned.bytes', set => {
                key_values => [ { name => 'assigned' }, { name => 'free' }, { name => 'prct_assigned' }, { name => 'prct_free' }, { name => 'total' } ],
                closure_custom_output => $self->can('custom_memory_output'),
                perfdatas => [
                    { template => '%d', unit => 'B', min => 0, max => 'total', label_extra_instance => 1 }
                ]
            }
        },
        { label => 'memory-assigned-prct', nlabel => 'system.memory.assigned.percentage', display_ok => 0, set => {
                key_values => [ { name => 'prct_assigned' }, { name => 'assigned' }, { name => 'free' }, { name => 'prct_free' }, { name => 'total' } ],
                closure_custom_output => $self->can('custom_memory_output'),
                perfdatas => [
                    { template => '%.2f', unit => '%', min => 0, max => 100, label_extra_instance => 1 }
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
        'exclude-system-name:s' => { name => 'exclude_system_name', default => '' }
    });

    return $self;
}

sub first_value {
    my ($value) = @_;

    # PCM metrics are arrays (one value per sample)
    return ref($value) eq 'ARRAY' ? $value->[0] : $value;
}

sub manage_selection {
    my ($self, %options) = @_;

    $self->{systems} = {};
    foreach my $system (@{$options{custom}->get_managed_systems()}) {
        next if is_excluded($system->{name}, $self->{option_results}->{include_system_name}, $self->{option_results}->{exclude_system_name}, output => $self->{output});

        my $metrics = $options{custom}->get_processed_metrics(system_uuid => $system->{uuid});
        my $util = ref($metrics) eq 'HASH' ? $metrics->{systemUtil}->{utilSamples}->[0]->{serverUtil} : undef;
        if (!defined($util)) {
            $self->{output}->output_add(long_msg => "skipping managed system '$system->{name}': no performance data (is PCM data collection enabled?)", debug => 1);
            next;
        }

        my $entry = { name => $system->{name} };
        my $cpu_total = first_value($util->{processor}->{totalProcUnits});
        my $cpu_used = first_value($util->{processor}->{utilizedProcUnits});
        if (defined($cpu_total) && $cpu_total > 0 && defined($cpu_used)) {
            $entry->{cpu_total} = $cpu_total;
            $entry->{cpu_used} = $cpu_used;
            $entry->{cpu_prct} = $cpu_used * 100 / $cpu_total;
        }

        # memory values are in MB
        my $mem_total = first_value($util->{memory}->{totalMem});
        my $mem_assigned = first_value($util->{memory}->{assignedMemToLpars});
        if (defined($mem_total) && $mem_total > 0 && defined($mem_assigned)) {
            $entry->{total} = $mem_total * 1024 * 1024;
            $entry->{assigned} = $mem_assigned * 1024 * 1024;
            $entry->{free} = $entry->{total} - $entry->{assigned};
            $entry->{prct_assigned} = $mem_assigned * 100 / $mem_total;
            $entry->{prct_free} = 100 - $entry->{prct_assigned};
        }

        $self->{systems}->{ $system->{name} } = $entry;
    }

    $self->{output}->option_exit(short_msg => 'No performance data found (check that PCM data collection is enabled on the managed systems).')
        if !%{$self->{systems}};
}

1;

__END__

=head1 MODE

Check managed systems processor and memory usage (Performance and Capacity Monitoring processed metrics).
PCM data collection must be enabled on the managed systems.

=over 8

=item B<--include-system-name>

Filter managed systems by name (can be a regexp).

=item B<--exclude-system-name>

Exclude managed systems by name (can be a regexp).

=item B<--warning-*> B<--critical-*>

Thresholds.
Can be: 'cpu-utilization' (%), 'cpu-utilized' (processor units), 'memory-assigned' (B), 'memory-assigned-prct' (%).

=back

=cut
