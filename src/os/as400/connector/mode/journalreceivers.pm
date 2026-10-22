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

package os::as400::connector::mode::journalreceivers;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;

sub prefix_receiver_output {
    my ($self, %options) = @_;

    return sprintf(
        "Journal '%s' receiver '%s' [attached: %s] ",
        $options{instance_value}->{journal},
        $options{instance_value}->{receiver},
        $options{instance_value}->{attached}
    );
}

sub prefix_global_output {
    my ($self, %options) = @_;

    return 'Attached journal receivers ';
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'global', cb_prefix_output => 'prefix_global_output', type => 0 },
        { name => 'receivers', type => 1, cb_prefix_output => 'prefix_receiver_output', message_multiple => 'All journal receivers sequence numbers are ok', skipped_code => { -10 => 1 } }
    ];

    $self->{maps_counters}->{global} = [
        { label => 'receivers-total', nlabel => 'journal.receivers.attached.count', display_ok => 0, set => {
                key_values => [ { name => 'total' } ],
                output_template => 'total: %s',
                perfdatas => [
                    { template => '%s', min => 0 }
                ]
            }
        }
    ];

    $self->{maps_counters}->{receivers} = [
        { label => 'sequence', nlabel => 'journal.receiver.sequence.count', critical_default => 8000000000, set => {
                key_values => [ { name => 'sequence' }, { name => 'journal' } ],
                output_template => 'last sequence number: %s',
                perfdatas => [
                    { template => '%s', min => 0, label_extra_instance => 1, instance_use => 'journal' }
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
        'min-sequence:s'    => { name => 'min_sequence', default => 0 },
        'include-maxopt3'   => { name => 'include_maxopt3' },
        'include-journal:s' => { name => 'include_journal' },
        'exclude-journal:s' => { name => 'exclude_journal' },
        'show-fix-command'  => { name => 'show_fix_command' }
    });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    if ($self->{option_results}->{min_sequence} !~ /^\d+$/) {
        $self->{output}->add_option_msg(short_msg => 'Option --min-sequence must be a positive integer');
        $self->{output}->option_exit();
    }
}

sub manage_selection {
    my ($self, %options) = @_;

    my $entries = $options{custom}->request_api(
        command => 'getJournalReceivers',
        args => {
            minSequence => $self->{option_results}->{min_sequence},
            excludeMaxOpt3 => defined($self->{option_results}->{include_maxopt3}) ? 0 : 1
        }
    );

    $self->{global} = { total => 0 };
    $self->{receivers} = {};
    foreach my $entry (@{$entries->{result}}) {
        my $journal = $entry->{journalLibrary} . '/' . $entry->{journalName};
        next if (defined($self->{option_results}->{include_journal}) && $self->{option_results}->{include_journal} ne '' &&
            $journal !~ /$self->{option_results}->{include_journal}/);
        next if (defined($self->{option_results}->{exclude_journal}) && $self->{option_results}->{exclude_journal} ne '' &&
            $journal =~ /$self->{option_results}->{exclude_journal}/);

        $self->{receivers}->{$journal} = {
            journal => $journal,
            receiver => $entry->{receiverLibrary} . '/' . $entry->{receiverName},
            attached => $entry->{attachTimestamp},
            sequence => $entry->{sequence}
        };
        $self->{global}->{total}++;

        if (defined($self->{option_results}->{show_fix_command})) {
            $self->{output}->output_add(
                long_msg => sprintf(
                    "journal '%s' (sequence %s): CHGJRN JRN(%s) JRNRCV(*GEN) SEQOPT(*RESET)",
                    $journal, $entry->{sequence}, $journal
                )
            );
        }
    }
}

1;

__END__

=head1 MODE

Check the last sequence number of attached journal receivers (QSYS2.JOURNAL_RECEIVER_INFO).
A journal close to its sequence limit must be reset: CHGJRN JRN(lib/journal) JRNRCV(*GEN) SEQOPT(*RESET).

=over 8

=item B<--min-sequence>

Only return receivers with a last sequence number greater than this value (default: 0).
Set it (e.g. 7000000000) to limit the amount of data and perfdata on systems with many journals.

=item B<--include-maxopt3>

Also check receivers created with RCVSIZOPT(*MAXOPT3) (excluded by default, their limit is much higher).

=item B<--include-journal>

Filter journals by 'library/journal' (can be a regexp).

=item B<--exclude-journal>

Exclude journals by 'library/journal' (can be a regexp).

=item B<--show-fix-command>

Display in the long output the CHGJRN command to reset each returned journal.

=item B<--warning-receivers-total> B<--critical-receivers-total>

Thresholds on the number of attached receivers returned.

=item B<--warning-sequence> B<--critical-sequence>

Thresholds on the last sequence number (default critical: 8000000000).

=back

=cut
