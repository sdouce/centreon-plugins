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

package os::as400::connector::mode::quickeddlicense;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold_ng);

sub custom_status_output {
    my ($self, %options) = @_;

    return sprintf(
        "status: %s [expiration: %s][check period: %s days]",
        $self->{result_values}->{status},
        $self->{result_values}->{expiration},
        $self->{result_values}->{check_days}
    );
}

sub prefix_license_output {
    my ($self, %options) = @_;

    return 'QuickEDD license ';
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'license', type => 0, cb_prefix_output => 'prefix_license_output' }
    ];

    $self->{maps_counters}->{license} = [
        {
            label => 'status',
            type => 2,
            warning_default => '%{status} =~ /expiring|expired/i',
            set => {
                key_values => [ { name => 'status' }, { name => 'expiration' }, { name => 'check_days' } ],
                closure_custom_output => $self->can('custom_status_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold_ng
            }
        },
        { label => 'expires', nlabel => 'quickedd.license.expires.days', set => {
                key_values => [ { name => 'days_left' } ],
                output_template => 'expires in %s days',
                perfdatas => [
                    { template => '%s', unit => 'd' }
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
        'lib-license:s' => { name => 'lib_license', default => 'PMEDHUSR' }
    });

    return $self;
}

sub manage_selection {
    my ($self, %options) = @_;

    my $entries = $options{custom}->request_api(
        command => 'getQuickEddLicense',
        args => { libLicense => $self->{option_results}->{lib_license} }
    );

    # keep the licence expiring first
    my $selected;
    foreach my $entry (@{$entries->{result}}) {
        $selected = $entry if (!defined($selected) || $entry->{daysLeft} < $selected->{daysLeft});
    }

    if (!defined($selected)) {
        $self->{output}->add_option_msg(short_msg => 'No license found in ' . $self->{option_results}->{lib_license} . '.EDHCHKLIC');
        $self->{output}->option_exit();
    }

    my $status = 'ok';
    if ($selected->{daysLeft} < 0) {
        $status = 'expired';
    } elsif ($selected->{inCheckPeriod}) {
        $status = 'expiring';
    }

    $self->{license} = {
        status => $status,
        expiration => $selected->{expiration},
        check_days => $selected->{checkDays},
        days_left => $selected->{daysLeft}
    };
}

1;

__END__

=head1 MODE

Check QuickEDD license expiration (table <lib-license>.EDHCHKLIC).

Status is 'expiring' when the current date is within the check period (column ZZCHK, in days)
before the expiration date, 'expired' after it.

=over 8

=item B<--lib-license>

Library of the EDHCHKLIC table (default: 'PMEDHUSR').

=item B<--unknown-status>

Define the conditions to match for the status to be UNKNOWN.
You can use the following variables: %{status}, %{expiration}, %{check_days}

=item B<--warning-status>

Define the conditions to match for the status to be WARNING (default: '%{status} =~ /expiring|expired/i').
You can use the following variables: %{status}, %{expiration}, %{check_days}

=item B<--critical-status>

Define the conditions to match for the status to be CRITICAL.
You can use the following variables: %{status}, %{expiration}, %{check_days}

=item B<--warning-expires> B<--critical-expires>

Thresholds on the number of days before expiration (e.g. --critical-expires=7: for 'less than 7 days').

=back

=cut
