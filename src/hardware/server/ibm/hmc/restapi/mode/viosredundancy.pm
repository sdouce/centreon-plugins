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

package hardware::server::ibm::hmc::restapi::mode::viosredundancy;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::misc qw/is_excluded/;
use centreon::plugins::constants qw(:counters);
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold_ng);

sub custom_redundancy_output {
    my ($self, %options) = @_;

    return sprintf(
        'running VIOS paths: %s/%s [%s]',
        $self->{result_values}->{viosRunning},
        $self->{result_values}->{viosConfigured},
        $self->{result_values}->{viosNames}
    );
}

sub custom_config_output {
    my ($self, %options) = @_;

    return 'configuration: ' . ($self->{result_values}->{issue} ne '' ? $self->{result_values}->{issue} : 'ok');
}

sub prefix_global_output {
    my ($self, %options) = @_;

    return 'Number of client virtual devices ';
}

sub prefix_device_output {
    my ($self, %options) = @_;

    return sprintf(
        "partition '%s' [system: %s] %s '%s' ",
        $options{instance_value}->{lpar},
        $options{instance_value}->{system},
        $options{instance_value}->{type},
        $options{instance_value}->{device}
    );
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'global', type => COUNTER_TYPE_GLOBAL, cb_prefix_output => 'prefix_global_output' },
        { name => 'devices', type => COUNTER_TYPE_INSTANCE, cb_prefix_output => 'prefix_device_output', message_multiple => 'All client virtual devices are redundant', skipped_code => { -10 => 1 } }
    ];

    $self->{maps_counters}->{global} = [
        { label => 'devices-detected', nlabel => 'vios.client.devices.detected.count', display_ok => 0, set => {
                key_values => [ { name => 'detected' } ],
                output_template => 'detected: %s',
                perfdatas => [
                    { template => '%s', min => 0 }
                ]
            }
        },
        { label => 'devices-nonredundant', nlabel => 'vios.client.devices.nonredundant.count', set => {
                key_values => [ { name => 'nonredundant' }, { name => 'detected' } ],
                output_template => 'non redundant: %s',
                perfdatas => [
                    { template => '%s', min => 0, max => 'detected' }
                ]
            }
        }
    ];

    $self->{maps_counters}->{devices} = [
        {
            label => 'redundancy-status',
            type => COUNTER_KIND_TEXT,
            warning_default => '%{viosRunning} < 2',
            set => {
                key_values => [
                    { name => 'viosRunning' }, { name => 'viosConfigured' }, { name => 'viosNames' },
                    { name => 'type' }, { name => 'device' }, { name => 'lpar' }, { name => 'system' }
                ],
                closure_custom_output => $self->can('custom_redundancy_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold_ng
            }
        },
        {
            label => 'configuration-status',
            type => COUNTER_KIND_TEXT,
            warning_default => '%{issue} ne ""',
            set => {
                key_values => [
                    { name => 'issue' }, { name => 'reservePolicy' },
                    { name => 'type' }, { name => 'device' }, { name => 'lpar' }, { name => 'system' }
                ],
                closure_custom_output => $self->can('custom_config_output'),
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
        'include-device-type:s' => { name => 'include_device_type', default => '' },
        'exclude-device-type:s' => { name => 'exclude_device_type', default => '' },
        'vios-group:s'          => { name => 'vios_group', default => 'ViosStorage,ViosSCSIMapping,ViosFCMapping' }
    });

    return $self;
}

sub add_device {
    my ($self, %options) = @_;

    my $device = $self->{work}->{ $options{key} } //= {
        system => $options{system},
        lpar_uuid => $options{lpar_uuid},
        type => $options{type},
        device => $options{device},
        configured => {},
        running => {},
        reserve => {},
        issues => []
    };
    $device->{configured}->{ $options{vios} } = 1;
    $device->{running}->{ $options{vios} } = 1 if $options{vios_running};
    $device->{reserve}->{ $options{vios} } = $options{reserve_policy} if defined($options{reserve_policy}) && $options{reserve_policy} ne '';
    push @{$device->{issues}}, $options{issue} if defined($options{issue});
}

sub manage_selection {
    my ($self, %options) = @_;

    $self->{global} = { detected => 0, nonredundant => 0 };
    $self->{devices} = {};
    $self->{work} = {};

    foreach my $system (@{$options{custom}->get_managed_systems()}) {
        next if is_excluded($system->{name}, $self->{option_results}->{include_system_name}, $self->{option_results}->{exclude_system_name}, output => $self->{output});

        my %lpar_names = map { $_->{uuid} => $_->{name} } @{$options{custom}->get_lpars(system_uuid => $system->{uuid})};
        $self->{lpar_names}->{ $system->{name} } = \%lpar_names;

        foreach my $vios (@{$options{custom}->get_vios(system_uuid => $system->{uuid}, group => $self->{option_results}->{vios_group})}) {
            my $running = $vios->{state} =~ /^running$/i ? 1 : 0;
            my %pv_reserve = map { $_->{name} => $_->{reserve_policy} } @{$vios->{disks}};

            foreach my $mapping (@{$vios->{scsi_mappings}}) {
                # virtual optical devices are not redundant by design
                next if $mapping->{storage_type} =~ /optical/i;

                # logical volumes or disks without unique identifier are local to the VIOS
                my $is_shared = $mapping->{storage_type} ne 'VirtualDisk' && $mapping->{udid} ne '';
                my $device_key = $is_shared ? $mapping->{udid} : $vios->{name} . ':' . $mapping->{storage_name};
                my $reserve = $mapping->{reserve_policy} ne '' ? $mapping->{reserve_policy} : $pv_reserve{ $mapping->{storage_name} };

                $self->add_device(
                    key => join('~', $system->{name}, $mapping->{client_uuid}, 'vscsi', $device_key),
                    system => $system->{name},
                    lpar_uuid => $mapping->{client_uuid},
                    type => 'vscsi',
                    device => $mapping->{storage_name},
                    vios => $vios->{name},
                    vios_running => $running,
                    reserve_policy => $mapping->{storage_type} eq 'PhysicalVolume' ? $reserve : undef
                );
            }

            foreach my $mapping (@{$vios->{fc_mappings}}) {
                $self->add_device(
                    key => join('~', $system->{name}, $mapping->{client_uuid}, 'vfc'),
                    system => $system->{name},
                    lpar_uuid => $mapping->{client_uuid},
                    type => 'vfc',
                    device => 'npiv',
                    vios => $vios->{name},
                    # a mapping without physical port does not provide any path
                    vios_running => $running && $mapping->{port_name} ne '',
                    issue => $mapping->{port_name} eq '' ? "no physical port on VIOS $vios->{name}" : undef
                );
            }
        }
    }

    foreach my $key (sort keys %{$self->{work}}) {
        my $device = $self->{work}->{$key};
        my $lpar = $self->{lpar_names}->{ $device->{system} }->{ $device->{lpar_uuid} };
        $lpar = $device->{lpar_uuid} unless defined($lpar);
        next if is_excluded($lpar, $self->{option_results}->{include_lpar_name}, $self->{option_results}->{exclude_lpar_name}, output => $self->{output})
            || is_excluded($device->{type}, $self->{option_results}->{include_device_type}, $self->{option_results}->{exclude_device_type}, output => $self->{output});

        my @issues = @{$device->{issues}};
        # a disk shared between several VIOS must not be locked by a SCSI reservation
        my @bad_reserve = grep { my $p = lc($device->{reserve}->{$_}); $p =~ s/[^a-z]//g; $p !~ /^(?:noreserve|prshared)$/ } sort keys %{$device->{reserve}};
        push @issues, 'reserve policy ' . join(', ', map { $_ . '=' . $device->{reserve}->{$_} } @bad_reserve)
            if scalar(keys %{$device->{configured}}) > 1 && @bad_reserve;

        my $instance = join('~', $device->{system}, $lpar, $device->{type}, $device->{device});
        $self->{devices}->{$instance} = {
            system => $device->{system},
            lpar => $lpar,
            type => $device->{type},
            device => $device->{device},
            viosRunning => scalar(keys %{$device->{running}}),
            viosConfigured => scalar(keys %{$device->{configured}}),
            viosNames => join(', ', sort keys %{$device->{configured}}),
            reservePolicy => join(', ', map { $_ . '=' . $device->{reserve}->{$_} } sort keys %{$device->{reserve}}),
            issue => join(', ', @issues)
        };
        $self->{global}->{detected}++;
        $self->{global}->{nonredundant}++ if $self->{devices}->{$instance}->{viosRunning} < 2;
    }

    $self->{output}->option_exit(short_msg => 'No virtual SCSI or virtual Fibre Channel mapping found (check --vios-group option).')
        if !%{$self->{devices}};
}

1;

__END__

=head1 MODE

Check the redundancy of client partitions virtual devices served by the Virtual I/O Servers (VIOS):
each virtual SCSI disk and each virtual Fibre Channel (NPIV) client must be served by at least two running VIOS.

A virtual SCSI disk is identified by its unique device ID (UDID): it is redundant when the same disk is mapped
to the same partition from several running VIOS. Disks backed by logical volumes are always local to one VIOS.
Virtual optical devices are ignored.

The configuration check raises an alert when a disk mapped from several VIOS does not use the C<no_reserve>
(or C<PR_shared>) reserve policy, or when a virtual Fibre Channel mapping is not attached to a physical port.

=over 8

=item B<--include-system-name>

Filter managed systems by name (can be a regexp).

=item B<--exclude-system-name>

Exclude managed systems by name (can be a regexp).

=item B<--include-lpar-name>

Filter client partitions by name (can be a regexp).

=item B<--exclude-lpar-name>

Exclude client partitions by name (can be a regexp).

=item B<--include-device-type>

Filter devices by type (can be a regexp). Types are C<vscsi> and C<vfc>.

=item B<--exclude-device-type>

Exclude devices by type (can be a regexp).

=item B<--vios-group>

Extended group(s) requested to the HMC to get mappings details (default: C<ViosStorage,ViosSCSIMapping,ViosFCMapping>).
Set an empty value to use the HMC default.

=item B<--warning-devices-detected>

Threshold.

=item B<--critical-devices-detected>

Threshold.

=item B<--warning-devices-nonredundant>

Threshold.

=item B<--critical-devices-nonredundant>

Threshold.

=item B<--unknown-redundancy-status>

Define the conditions to match for the status to be UNKNOWN.
You can use the following variables: C<%{viosRunning}>, C<%{viosConfigured}>, C<%{viosNames}>, C<%{type}>, C<%{device}>, C<%{lpar}>, C<%{system}>

=item B<--warning-redundancy-status>

Define the conditions to match for the status to be WARNING (default: C<%{viosRunning} < 2>).
You can use the following variables: C<%{viosRunning}>, C<%{viosConfigured}>, C<%{viosNames}>, C<%{type}>, C<%{device}>, C<%{lpar}>, C<%{system}>

=item B<--critical-redundancy-status>

Define the conditions to match for the status to be CRITICAL.
You can use the following variables: C<%{viosRunning}>, C<%{viosConfigured}>, C<%{viosNames}>, C<%{type}>, C<%{device}>, C<%{lpar}>, C<%{system}>

=item B<--unknown-configuration-status>

Define the conditions to match for the status to be UNKNOWN.
You can use the following variables: C<%{issue}>, C<%{reservePolicy}>, C<%{type}>, C<%{device}>, C<%{lpar}>, C<%{system}>

=item B<--warning-configuration-status>

Define the conditions to match for the status to be WARNING (default: C<%{issue} ne "">).
You can use the following variables: C<%{issue}>, C<%{reservePolicy}>, C<%{type}>, C<%{device}>, C<%{lpar}>, C<%{system}>

=item B<--critical-configuration-status>

Define the conditions to match for the status to be CRITICAL.
You can use the following variables: C<%{issue}>, C<%{reservePolicy}>, C<%{type}>, C<%{device}>, C<%{lpar}>, C<%{system}>

=back

=cut
