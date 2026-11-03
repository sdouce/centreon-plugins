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

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        {
            name => 'vios', type => COUNTER_TYPE_MULTIPLE, cb_prefix_output => 'prefix_vios_output', cb_long_output => 'vios_long_output',
            message_multiple => 'All VIOS disks are ok', indent_long_output => '    ',
            group => [
                { name => 'global', type => COUNTER_MULTIPLE_INSTANCE, skipped_code => { -10 => 1 } },
                { name => 'disks', type => COUNTER_MULTIPLE_SUBINSTANCE, display_long => 1, cb_prefix_output => 'prefix_disk_output', message_multiple => 'all disks are ok', skipped_code => { -10 => 1 } }
            ]
        }
    ];

    $self->{maps_counters}->{global} = [
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
        'vios-group:s'          => { name => 'vios_group', default => 'ViosStorage' }
    });

    return $self;
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

            my $entry = { name => $vios->{name}, system => $system->{name}, global => { detected => 0, failed => 0 }, disks => {} };
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

    $self->{output}->option_exit(short_msg => 'No running VIOS found.')
        if !%{$self->{vios}};
}

1;

__END__

=head1 MODE

Check physical volumes (disks) state seen by each running Virtual I/O Server (VIOS).

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
