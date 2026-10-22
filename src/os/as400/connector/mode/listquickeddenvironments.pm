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
package os::as400::connector::mode::listquickeddenvironments;

use base qw(centreon::plugins::mode);

use strict;
use warnings;

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;

    $options{options}->add_options(arguments => {
        'lib-qedd:s' => { name => 'lib_qedd' },
        'lib-prog:s' => { name => 'lib_prog' }
    });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    if (!defined($self->{option_results}->{lib_prog}) || $self->{option_results}->{lib_prog} eq '') {
        $self->{output}->add_option_msg(short_msg => 'Need to specify --lib-prog option (library of the PZHAWRKM service program)');
        $self->{output}->option_exit();
    }
}

sub manage_selection {
    my ($self, %options) = @_;

    my $args = { libProg => $self->{option_results}->{lib_prog} };
    $args->{libQedd} = $self->{option_results}->{lib_qedd}
        if (defined($self->{option_results}->{lib_qedd}) && $self->{option_results}->{lib_qedd} ne '');
    return $options{custom}->request_api(command => 'listQuickEddEnvironments', args => $args);
}

sub run {
    my ($self, %options) = @_;

    my $results = $self->manage_selection(%options);
    foreach my $entry (@{$results->{result}}) {
        $self->{output}->output_add(
            long_msg => sprintf('[name: %s][description: %s]', $entry->{name}, defined($entry->{description}) ? $entry->{description} : '')
        );
    }
    $self->{output}->output_add(long_msg => 'raw getEnvList output: ' . $results->{message}, debug => 1)
        if (defined($results->{message}));

    $self->{output}->output_add(
        severity => 'OK',
        short_msg => 'List QuickEDD environments:'
    );
    $self->{output}->display(nolabel => 1, force_ignore_perfdata => 1, force_long_output => 1);
    $self->{output}->exit();
}

sub disco_format {
    my ($self, %options) = @_;

    $self->{output}->add_disco_format(elements => ['name', 'description']);
}

sub disco_show {
    my ($self, %options) = @_;

    my $results = $self->manage_selection(%options);
    foreach my $entry (@{$results->{result}}) {
        $self->{output}->add_disco_entry(
            name => $entry->{name},
            description => defined($entry->{description}) ? $entry->{description} : ''
        );
    }
}

1;

__END__

=head1 MODE

List QuickEDD environments (getEnvList of the PZHAWRKM service program).

=over 8

=item B<--lib-prog>

Library of the QuickEDD service program PZHAWRKM (required).

=item B<--lib-qedd>

QuickEDD library to add to the library list.

=back

=cut
