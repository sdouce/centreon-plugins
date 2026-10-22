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

package os::as400::connector::mode::sql;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;

sub prefix_row_output {
    my ($self, %options) = @_;

    return "'" . $options{instance_value}->{instance} . "' ";
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'global', type => 0 },
        { name => 'rows', type => 1, cb_prefix_output => 'prefix_row_output', message_multiple => 'All values are ok', skipped_code => { -10 => 1 } }
    ];

    $self->{maps_counters}->{global} = [
        { label => 'rows', nlabel => 'sql.rows.count', set => {
                key_values => [ { name => 'rows' } ],
                output_template => 'SQL request returned %s row(s)',
                perfdatas => [
                    { template => '%s', min => 0 }
                ]
            }
        }
    ];

    $self->{maps_counters}->{rows} = [
        { label => 'value', nlabel => 'sql.value', set => {
                key_values => [ { name => 'value' }, { name => 'instance' } ],
                output_template => 'value: %s',
                perfdatas => [
                    { template => '%s', label_extra_instance => 1, instance_use => 'instance' }
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
        'sql-request:s'      => { name => 'sql_request' },
        'sql-request-file:s' => { name => 'sql_request_file' },
        'max-rows:s'         => { name => 'max_rows', default => 100 },
        'value-column:s'     => { name => 'value_column' },
        'instance-column:s'  => { name => 'instance_column' }
    });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    if (defined($self->{option_results}->{sql_request_file}) && $self->{option_results}->{sql_request_file} ne '') {
        my $fh;
        if (!open($fh, '<', $self->{option_results}->{sql_request_file})) {
            $self->{output}->add_option_msg(short_msg => "Cannot read file '" . $self->{option_results}->{sql_request_file} . "': $!");
            $self->{output}->option_exit();
        }
        local $/;
        $self->{option_results}->{sql_request} = <$fh>;
        close($fh);
    }
    if (!defined($self->{option_results}->{sql_request}) || $self->{option_results}->{sql_request} =~ /^\s*$/) {
        $self->{output}->add_option_msg(short_msg => 'Need to specify --sql-request or --sql-request-file option');
        $self->{output}->option_exit();
    }
    if ($self->{option_results}->{max_rows} !~ /^\d+$/ || $self->{option_results}->{max_rows} == 0) {
        $self->{output}->add_option_msg(short_msg => 'Option --max-rows must be a positive integer');
        $self->{output}->option_exit();
    }
}

sub manage_selection {
    my ($self, %options) = @_;

    my $request = $self->{option_results}->{sql_request};
    $request =~ s/^\s*--.*$//mg;    # remove SQL comments

    my $response = $options{custom}->request_api(
        command => 'executeSql',
        args => { request => $request, maxRows => $self->{option_results}->{max_rows} }
    );
    my $result = $response->{result}->[0];
    my @columns = @{$result->{columns} || []};
    my @rows = @{$result->{rows} || []};

    # column positions (case insensitive)
    my %pos;
    for (my $i = 0; $i <= $#columns; $i++) {
        $pos{ uc($columns[$i]) } = $i;
    }
    my ($value_idx, $instance_idx);
    if (defined($self->{option_results}->{value_column}) && $self->{option_results}->{value_column} ne '') {
        $value_idx = $pos{ uc($self->{option_results}->{value_column}) };
        if (!defined($value_idx)) {
            $self->{output}->add_option_msg(short_msg => "Column '" . $self->{option_results}->{value_column} . "' not found (columns: " . join(', ', @columns) . ')');
            $self->{output}->option_exit();
        }
        $instance_idx = 0;
        if (defined($self->{option_results}->{instance_column}) && $self->{option_results}->{instance_column} ne '') {
            $instance_idx = $pos{ uc($self->{option_results}->{instance_column}) };
            if (!defined($instance_idx)) {
                $self->{output}->add_option_msg(short_msg => "Column '" . $self->{option_results}->{instance_column} . "' not found (columns: " . join(', ', @columns) . ')');
                $self->{output}->option_exit();
            }
        }
    }

    $self->{global} = { rows => scalar(@rows) };
    $self->{rows} = {};
    my $num = 0;
    foreach my $row (@rows) {
        $num++;
        $self->{output}->output_add(
            long_msg => join('', map { '[' . $columns[$_] . ': ' . (defined($row->[$_]) ? $row->[$_] : 'NULL') . ']' } (0 .. $#columns))
        );
        next if (!defined($value_idx));

        my $value = $row->[$value_idx];
        if (!defined($value) || $value !~ /^\s*-?\d+(?:\.\d+)?\s*$/) {
            $self->{output}->add_option_msg(short_msg => "Row $num: column '" . $columns[$value_idx] . "' is not numeric: " . (defined($value) ? $value : 'NULL'));
            $self->{output}->option_exit();
        }
        my $instance = defined($row->[$instance_idx]) && $instance_idx != $value_idx ? $row->[$instance_idx] : 'row' . $num;
        $value =~ s/\s+//g;
        $self->{rows}->{$instance . '_' . $num} = { instance => $instance, value => $value };
    }

    if ($result->{truncated}) {
        $self->{output}->output_add(
            long_msg => 'result truncated to ' . $self->{option_results}->{max_rows} . ' rows (use --max-rows)'
        );
    }
}

1;

__END__

=head1 MODE

Execute a read-only SQL request (SELECT, WITH, VALUES) through the connector (jt400 JDBC driver).

Rows are displayed in the long output (use --verbose).

Examples:

Look for a table:
--mode=sql --sql-request="SELECT TABLE_SCHEMA, TABLE_NAME FROM QSYS2.SYSTABLES WHERE TABLE_NAME = 'EDHCHKLIC'" --verbose

Alert when a query returns rows:
--mode=sql --sql-request="SELECT JOB_NAME FROM TABLE(QSYS2.ACTIVE_JOB_INFO()) X WHERE JOB_STATUS = 'MSGW'" --critical-rows=0

Threshold on a numeric column, one metric per row:
--mode=sql --sql-request="SELECT JOURNAL_NAME, LAST_SEQUENCE_NUMBER FROM QSYS2.JOURNAL_RECEIVER_INFO WHERE STATUS='ATTACHED'"
--instance-column=JOURNAL_NAME --value-column=LAST_SEQUENCE_NUMBER --critical-value=8000000000

=over 8

=item B<--sql-request>

SQL request to execute (only one, read-only).

=item B<--sql-request-file>

Read the SQL request from a file.

=item B<--max-rows>

Maximum number of rows returned (default: 100).

=item B<--value-column>

Numeric column used for the 'value' thresholds and perfdata (one per row).

=item B<--instance-column>

Column used as instance name for the 'value' metric (default: first column).

=item B<--warning-rows> B<--critical-rows>

Thresholds on the number of rows returned.

=item B<--warning-value> B<--critical-value>

Thresholds on the value of --value-column.

=back

=cut
