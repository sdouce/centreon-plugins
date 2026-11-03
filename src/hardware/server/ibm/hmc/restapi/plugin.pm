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

package hardware::server::ibm::hmc::restapi::plugin;

use strict;
use warnings;
use base qw(centreon::plugins::script_custom);

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;

    $self->{modes} = {
        'list-managed-systems'   => 'hardware::server::ibm::hmc::restapi::mode::listmanagedsystems',
        'lpars'                  => 'hardware::server::ibm::hmc::restapi::mode::lpars',
        'managed-systems'        => 'hardware::server::ibm::hmc::restapi::mode::managedsystems',
        'shared-processor-pools' => 'hardware::server::ibm::hmc::restapi::mode::sharedprocessorpools',
        'system-usage'           => 'hardware::server::ibm::hmc::restapi::mode::systemusage',
        'vios'                   => 'hardware::server::ibm::hmc::restapi::mode::vios',
        'vios-disks'             => 'hardware::server::ibm::hmc::restapi::mode::viosdisks',
        'vios-errors'            => 'hardware::server::ibm::hmc::restapi::mode::vioserrors',
        'vios-redundancy'        => 'hardware::server::ibm::hmc::restapi::mode::viosredundancy'
    };

    $self->{custom_modes}->{api} = 'hardware::server::ibm::hmc::restapi::custom::api';
    return $self;
}

1;

__END__

=head1 PLUGIN DESCRIPTION

Check IBM Power servers (managed systems, LPAR, VIOS) through the IBM Hardware Management Console (HMC) REST API.
No SSH access to the HMC is required.

=cut
