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

package hardware::server::ibm::hmc::restapi::mode::listmanagedsystems;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::misc qw/is_excluded/;

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;

    $options{options}->add_options(arguments => {
        'include-system-name:s' => { name => 'include_system_name', default => '' },
        'exclude-system-name:s' => { name => 'exclude_system_name', default => '' }
    });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);
}

sub manage_selection {
    my ($self, %options) = @_;

    $self->{systems} = [];
    foreach my $system (sort { $a->{name} cmp $b->{name} } @{$options{custom}->get_managed_systems()}) {
        next if is_excluded($system->{name}, $self->{option_results}->{include_system_name}, $self->{option_results}->{exclude_system_name}, output => $self->{output});
        push @{$self->{systems}}, $system;
    }
}

sub run {
    my ($self, %options) = @_;

    $self->manage_selection(%options);
    foreach my $system (@{$self->{systems}}) {
        $self->{output}->output_add(
            long_msg => sprintf(
                '[uuid: %s][name: %s][state: %s][type: %s][model: %s][serial: %s]',
                $system->{uuid},
                $system->{name},
                $system->{state},
                defined($system->{machine_type}) ? $system->{machine_type} : '',
                defined($system->{model}) ? $system->{model} : '',
                defined($system->{serial}) ? $system->{serial} : ''
            )
        );
    }

    $self->{output}->output_add(
        severity => 'OK',
        short_msg => 'List managed systems:'
    );
    $self->{output}->display(nolabel => 1, force_ignore_perfdata => 1, force_long_output => 1);
    $self->{output}->exit();
}

sub disco_format {
    my ($self, %options) = @_;

    $self->{output}->add_disco_format(elements => ['uuid', 'name', 'state', 'type', 'model', 'serial']);
}

sub disco_show {
    my ($self, %options) = @_;

    $self->manage_selection(%options);
    foreach my $system (@{$self->{systems}}) {
        $self->{output}->add_disco_entry(
            uuid => $system->{uuid},
            name => $system->{name},
            state => $system->{state},
            type => defined($system->{machine_type}) ? $system->{machine_type} : '',
            model => defined($system->{model}) ? $system->{model} : '',
            serial => defined($system->{serial}) ? $system->{serial} : ''
        );
    }
}

1;

__END__

=head1 MODE

List managed systems (IBM Power servers) of the HMC.
This mode also supports service discovery (C<--disco-format>, C<--disco-show>).

=over 8

=item B<--include-system-name>

Filter managed systems by name (can be a regexp).

=item B<--exclude-system-name>

Exclude managed systems by name (can be a regexp).

=back

=cut
