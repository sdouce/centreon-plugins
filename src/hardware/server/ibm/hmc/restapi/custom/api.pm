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

package hardware::server::ibm::hmc::restapi::custom::api;

use strict;
use warnings;
use centreon::plugins::http;
use centreon::plugins::statefile;
use centreon::plugins::misc qw/json_decode is_empty/;
use centreon::plugins::constants qw(:messages);
use Digest::SHA qw(sha256_hex);
use XML::LibXML;
use Time::HiRes qw(sleep);

my $NS_WEB = 'http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/';

sub new {
    my ($class, %options) = @_;
    my $self  = {};
    bless $self, $class;

    if (!defined($options{output})) {
        print "Class Custom: Need to specify 'output' argument.\n";
        exit 3;
    }
    $options{output}->option_exit(short_msg => "Class Custom: Need to specify 'options' argument.")
        unless $options{options};

    if (!defined($options{noptions})) {
        $options{options}->add_options(arguments => {
            'hostname:s'             => { name => 'hostname', default => '' },
            'port:s'                 => { name => 'port', default => 12443 },
            'proto:s'                => { name => 'proto', default => 'https' },
            'api-username:s'         => { name => 'api_username', default => '' },
            'api-password:s'         => { name => 'api_password', default => '' },
            'timeout:s'              => { name => 'timeout', default => 50 },
            'job-timeout:s'          => { name => 'job_timeout', default => 120 },
            'unknown-http-status:s'  => { name => 'unknown_http_status', default => '%{http_code} < 200 or %{http_code} >= 300' },
            'warning-http-status:s'  => { name => 'warning_http_status' },
            'critical-http-status:s' => { name => 'critical_http_status' }
        });
    }
    $options{options}->add_help(package => __PACKAGE__, sections => 'REST API OPTIONS', once => 1);

    $self->{output} = $options{output};
    $self->{http} = centreon::plugins::http->new(%options, default_backend => 'curl');
    $self->{cache_connect} = centreon::plugins::statefile->new(%options);

    return $self;
}

sub set_options {
    my ($self, %options) = @_;

    $self->{option_results} = $options{option_results};
}

sub set_defaults {}

sub check_options {
    my ($self, %options) = @_;

    $self->{$_} = $self->{option_results}->{$_}
        foreach qw/hostname port proto api_username api_password timeout job_timeout unknown_http_status warning_http_status critical_http_status/;

    $self->{output}->option_exit(short_msg => 'Need to specify --hostname option.')
        if $self->{hostname} eq '';
    $self->{output}->option_exit(short_msg => 'Need to specify --api-username option.')
        if $self->{api_username} eq '';
    $self->{output}->option_exit(short_msg => 'Need to specify --api-password option.')
        if $self->{api_password} eq '';
    $self->{output}->option_exit(short_msg => 'Wrong --job-timeout option.')
        if $self->{job_timeout} !~ /^\d+$/;

    $self->{cache_connect}->check_options(option_results => $self->{option_results});

    return 0;
}

sub get_connection_info {
    my ($self, %options) = @_;

    return $self->{hostname} . ':' . $self->{port} . '_' . $self->{api_username};
}

sub settings {
    my ($self, %options) = @_;

    return if $self->{settings_done};
    $self->{option_results}->{timeout} = $self->{timeout};
    $self->{http}->set_options(%{$self->{option_results}});
    $self->{settings_done} = 1;
}

sub xml_escape {
    my ($value) = @_;

    $value =~ s/&/&amp;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    $value =~ s/"/&quot;/g;
    $value =~ s/'/&apos;/g;
    return $value;
}

sub parse_xml {
    my ($self, %options) = @_;

    my $doc;
    eval {
        $doc = XML::LibXML->new(no_network => 1, load_ext_dtd => 0, expand_entities => 0)->parse_string($options{content});
    };
    $self->{output}->option_exit(short_msg => 'Cannot decode XML response (add --debug option to display returned content)')
        if $@ || !defined($doc);

    return $doc;
}

# XPath helper: 'A/B' becomes './*[local-name()="A"]/*[local-name()="B"]' (namespace agnostic)
sub xpath {
    my ($path) = @_;

    return './' . join('/', map { $_ eq '..' || $_ eq '*' ? $_ : '*[local-name()="' . $_ . '"]' } split(/\//, $path));
}

sub xnodes {
    my ($node, $path) = @_;

    return () unless defined($node);
    return $node->findnodes(xpath($path));
}

sub xnode {
    my ($node, $path) = @_;

    my @nodes = xnodes($node, $path);
    return $nodes[0];
}

sub xtext {
    my ($node, $path, $default) = @_;

    my $found = xnode($node, $path);
    return $default unless defined($found);
    my $value = $found->textContent();
    $value =~ s/^\s+|\s+$//g;
    return $value eq '' ? $default : $value;
}

sub clean_session {
    my ($self, %options) = @_;

    $self->{session} = undef;
    $self->{cache_connect}->write(data => { updated => time() });
}

sub get_session {
    my ($self, %options) = @_;

    return $self->{session} if defined($self->{session});

    # HMC limits the number of opened sessions: the session is kept in a cache file and reused
    my $has_cache_file = $self->{cache_connect}->read(statefile => 'ibm_hmc_restapi_' . sha256_hex($self->get_connection_info()));
    my $session = $self->{cache_connect}->get(name => 'session');
    my $sha_secret_cache = $self->{cache_connect}->get(name => 'sha_secret');
    my $sha_secret = sha256_hex($self->{api_username} . $self->{api_password});

    if ($has_cache_file == 0 || is_empty($session) || !defined($sha_secret_cache) || $sha_secret_cache ne $sha_secret) {
        my $body = sprintf(
            '<LogonRequest xmlns="%s" schemaVersion="V1_0"><UserID>%s</UserID><Password>%s</Password></LogonRequest>',
            $NS_WEB, xml_escape($self->{api_username}), xml_escape($self->{api_password})
        );
        my $content = $self->{http}->request(
            method => 'PUT',
            hostname => $self->{hostname},
            url_path => '/rest/api/web/Logon',
            query_form_post => $body,
            header => [
                'Content-Type: application/vnd.ibm.powervm.web+xml; type=LogonRequest',
                'Accept: application/vnd.ibm.powervm.web+xml; type=LogonResponse',
                'X-Audit-Memento: centreon'
            ],
            unknown_status => $self->{unknown_http_status},
            warning_status => $self->{warning_http_status},
            critical_status => $self->{critical_http_status}
        );

        my $doc = $self->parse_xml(content => $content);
        $session = xtext($doc->documentElement(), 'X-API-Session');
        $self->{output}->option_exit(short_msg => 'Cannot find X-API-Session in logon response')
            if is_empty($session);

        $self->{cache_connect}->write(data => {
            updated => time(),
            session => $session,
            sha_secret => $sha_secret
        });
    }

    $self->{session} = $session;
    return $session;
}

sub request {
    my ($self, %options) = @_;

    $self->settings();
    # links returned by the HMC are absolute URLs: only keep the path
    my $path = $options{path};
    $path =~ s/^https?:\/\/[^\/]+//;

    my %request = (
        method => defined($options{method}) ? $options{method} : 'GET',
        hostname => $self->{hostname},
        url_path => $path,
        defined($options{body}) ? (query_form_post => $options{body}) : ()
    );
    my $headers = [ 'Accept: ' . $options{accept}, defined($options{headers}) ? @{$options{headers}} : () ];

    my $content = $self->{http}->request(
        %request,
        header => [ @$headers, 'X-API-Session: ' . $self->get_session() ],
        unknown_status => '', warning_status => '', critical_status => ''
    );

    # session may have expired: log on again and retry
    if ($self->{http}->get_code() == 401 || $self->{http}->get_code() == 403) {
        $self->clean_session();
        $content = $self->{http}->request(
            %request,
            header => [ @$headers, 'X-API-Session: ' . $self->get_session() ],
            unknown_status => '', warning_status => '', critical_status => ''
        );
    }

    # 204: no content (empty collection, no PCM data...)
    return undef if $self->{http}->get_code() == 204;

    if ($self->{http}->get_code() < 200 || $self->{http}->get_code() >= 300) {
        $self->{output}->option_exit(
            short_msg => sprintf(
                "API request '%s' failed [code: '%s'] [message: '%s']",
                $path, $self->{http}->get_code(), $self->{http}->get_message()
            )
        );
    }

    return $content;
}

sub request_json {
    my ($self, %options) = @_;

    my $content = $self->request(%options, accept => 'application/json');
    return undef if is_empty($content);

    my $decoded = json_decode($content, output => $self->{output}, no_exit => 1);
    $self->{output}->option_exit(short_msg => MSG_JSON_DECODE_ERROR)
        unless defined($decoded);
    return $decoded;
}

sub request_feed {
    my ($self, %options) = @_;

    my $content = $self->request(%options, accept => 'application/atom+xml');
    return () if is_empty($content);

    my $doc = $self->parse_xml(content => $content);
    my @objects;
    foreach my $entry ($doc->findnodes('//*[local-name()="entry"]')) {
        my ($object) = $entry->findnodes('./*[local-name()="content"]/*');
        my $id = xtext($entry, 'id');
        push @objects, { id => $id, node => $object, entry => $entry } if defined($object);
    }
    return @objects;
}

sub get_managed_systems {
    my ($self, %options) = @_;

    return $self->{managed_systems} if defined($self->{managed_systems});

    my $data = $self->request_json(path => '/rest/api/uom/ManagedSystem/quick/All');
    $self->{managed_systems} = [];
    foreach (ref($data) eq 'ARRAY' ? @$data : ()) {
        push @{$self->{managed_systems}}, {
            uuid => $_->{UUID},
            name => $_->{SystemName},
            state => defined($_->{State}) ? $_->{State} : 'unknown',
            machine_type => $_->{MachineType},
            model => $_->{Model},
            serial => $_->{SerialNumber},
            raw => $_
        };
    }

    return $self->{managed_systems};
}

sub get_lpars {
    my ($self, %options) = @_;

    my $data = $self->request_json(path => '/rest/api/uom/ManagedSystem/' . $options{system_uuid} . '/LogicalPartition/quick/All');
    my $lpars = [];
    foreach (ref($data) eq 'ARRAY' ? @$data : ()) {
        push @$lpars, {
            uuid => $_->{UUID},
            id => $_->{PartitionID},
            name => $_->{PartitionName},
            type => $_->{PartitionType},
            state => defined($_->{PartitionState}) ? $_->{PartitionState} : 'unknown',
            rmc_state => defined($_->{RMCState}) ? $_->{RMCState} :
                defined($_->{ResourceMonitoringControlState}) ? $_->{ResourceMonitoringControlState} : '',
            reference_code => defined($_->{ReferenceCode}) ? $_->{ReferenceCode} : ''
        };
    }

    return $lpars;
}

sub uuid_from_href {
    my ($href) = @_;

    return '' unless defined($href);
    $href =~ s/\?.*$//;
    $href =~ s/\/+$//;
    $href =~ /([^\/]+)$/;
    return defined($1) ? $1 : '';
}

sub get_vios {
    my ($self, %options) = @_;

    # storage and mapping details are in extended groups that are not always returned by default
    my $path = '/rest/api/uom/ManagedSystem/' . $options{system_uuid} . '/VirtualIOServer';
    $path .= '?group=' . $options{group} if defined($options{group}) && $options{group} ne '';
    my $vios = [];

    foreach my $object ($self->request_feed(path => $path)) {
        my $node = $object->{node};
        my $item = {
            uuid => xtext($node, 'PartitionUUID', uuid_from_href($object->{id})),
            id => xtext($node, 'PartitionID', ''),
            name => xtext($node, 'PartitionName', ''),
            state => xtext($node, 'PartitionState', 'unknown'),
            rmc_state => xtext($node, 'ResourceMonitoringControlState', 'unknown'),
            reference_code => xtext($node, 'ReferenceCode', ''),
            os_version => xtext($node, 'OperatingSystemVersion', ''),
            disks => [],
            scsi_mappings => [],
            fc_mappings => []
        };

        foreach my $pv (xnodes($node, 'PhysicalVolumes/PhysicalVolume')) {
            push @{$item->{disks}}, {
                name => xtext($pv, 'VolumeName', ''),
                state => xtext($pv, 'VolumeState', ''),
                udid => xtext($pv, 'UniqueDeviceID', xtext($pv, 'VolumeUniqueID', '')),
                reserve_policy => xtext($pv, 'ReservePolicy', ''),
                capacity => xtext($pv, 'VolumeCapacity', ''),
                description => xtext($pv, 'Description', ''),
                location => xtext($pv, 'LocationCode', '')
            };
        }

        foreach my $mapping (xnodes($node, 'VirtualSCSIMappings/VirtualSCSIMapping')) {
            my $client = xnode($mapping, 'AssociatedLogicalPartition');
            my ($storage) = xnodes($mapping, 'Storage/*');
            next if !defined($client) || !defined($storage);
            push @{$item->{scsi_mappings}}, {
                client_uuid => uuid_from_href($client->getAttribute('href')),
                storage_type => $storage->localname(),
                storage_name => xtext($storage, 'VolumeName', xtext($storage, 'DiskName', xtext($storage, 'UnitName', xtext($storage, 'MediaName', '')))),
                udid => xtext($storage, 'UniqueDeviceID', xtext($storage, 'VolumeUniqueID', '')),
                reserve_policy => xtext($storage, 'ReservePolicy', '')
            };
        }

        foreach my $mapping (xnodes($node, 'VirtualFibreChannelMappings/VirtualFibreChannelMapping')) {
            my $client = xnode($mapping, 'AssociatedLogicalPartition');
            next if !defined($client);
            push @{$item->{fc_mappings}}, {
                client_uuid => uuid_from_href($client->getAttribute('href')),
                port_name => xtext($mapping, 'Port/PortName', ''),
                port_wwpn => xtext($mapping, 'Port/WWPN', '')
            };
        }

        push @$vios, $item;
    }

    return $vios;
}

sub get_processed_metrics {
    my ($self, %options) = @_;

    my $content = $self->request(
        path => '/rest/api/pcm/ManagedSystem/' . $options{system_uuid} . '/ProcessedMetrics?NoOfSamples=1',
        accept => 'application/atom+xml'
    );
    return undef if is_empty($content);

    my $doc = $self->parse_xml(content => $content);
    foreach my $link ($doc->findnodes('//*[local-name()="link"]')) {
        my $href = $link->getAttribute('href');
        next if !defined($href) || $href !~ /\.json$/;
        return $self->request_json(path => $href);
    }

    return undef;
}

sub get_management_console_uuid {
    my ($self, %options) = @_;

    return $self->{mc_uuid} if defined($self->{mc_uuid});

    my @objects = $self->request_feed(path => '/rest/api/uom/ManagementConsole');
    $self->{output}->option_exit(short_msg => 'Cannot find management console UUID')
        unless @objects;
    $self->{mc_uuid} = uuid_from_href($objects[0]->{id});
    return $self->{mc_uuid};
}

# Submit an HMC CLI command to the CLIRunner job of the REST API. Returns the job ID.
sub submit_cli_job {
    my ($self, %options) = @_;

    my $body = sprintf(
        '<JobRequest:JobRequest xmlns:JobRequest="%s" xmlns="%s" schemaVersion="V1_0">' .
        '<RequestedOperation kb="CUR" kxe="false" schemaVersion="V1_0">' .
        '<OperationName kb="ROR" kxe="false">CLIRunner</OperationName>' .
        '<GroupName kb="ROR" kxe="false">ManagementConsole</GroupName>' .
        '</RequestedOperation>' .
        '<JobParameters kb="CUR" kxe="false" schemaVersion="V1_0">' .
        '<JobParameter schemaVersion="V1_0"><ParameterName kb="ROR" kxe="false">cmd</ParameterName>' .
        '<ParameterValue kb="CUR" kxe="false">%s</ParameterValue></JobParameter>' .
        '<JobParameter schemaVersion="V1_0"><ParameterName kb="ROR" kxe="false">acknowledgeThisAPIMayGoAwayInTheFuture</ParameterName>' .
        '<ParameterValue kb="CUR" kxe="false">true</ParameterValue></JobParameter>' .
        '</JobParameters></JobRequest:JobRequest>',
        $NS_WEB, $NS_WEB, xml_escape($options{command})
    );

    my $content = $self->request(
        method => 'PUT',
        path => '/rest/api/uom/ManagementConsole/' . $self->get_management_console_uuid() . '/do/CLIRunner',
        body => $body,
        accept => 'application/atom+xml',
        headers => [ 'Content-Type: application/vnd.ibm.powervm.web+xml; type=JobRequest' ]
    );
    my $doc = $self->parse_xml(content => $content);
    my ($job_id) = map { $_->textContent() } $doc->findnodes('//*[local-name()="JobID"]');
    return $job_id;
}

# Wait for several CLIRunner jobs running in parallel on the HMC.
# Returns { job_id => { status, rc, output } }.
sub wait_cli_jobs {
    my ($self, %options) = @_;

    my $results = {};
    my %pending = map { $_ => 1 } @{$options{job_ids}};
    my $deadline = time() + $self->{job_timeout};
    my $interval = 0.5;
    while (%pending) {
        foreach my $job_id (sort keys %pending) {
            my $content = $self->request(path => '/rest/api/uom/jobs/' . $job_id, accept => 'application/atom+xml');
            my $doc = $self->parse_xml(content => $content);
            my ($status) = map { $_->textContent() } $doc->findnodes('//*[local-name()="Status"]');
            $status = '' unless defined($status);
            next if $status =~ /^(?:NOT_STARTED|RUNNING|)$/;

            my $params = {};
            foreach my $param ($doc->findnodes('//*[local-name()="Results"]/*[local-name()="JobParameter"]')) {
                $params->{ xtext($param, 'ParameterName', '') } = xtext($param, 'ParameterValue', '');
            }
            $results->{$job_id} = {
                status => $status,
                rc => defined($params->{returnCode}) ? $params->{returnCode} : '',
                output => defined($params->{result}) ? $params->{result} :
                    join("\n", map { $params->{$_} } grep { $_ !~ /^(?:returnCode|rc)$/ } sort keys %$params)
            };
            delete $pending{$job_id};
        }
        last if !%pending;

        if (time() > $deadline) {
            $results->{$_} = { status => 'TIMEOUT', rc => '', output => "job $_ still running after $self->{job_timeout}s" }
                foreach keys %pending;
            last;
        }
        sleep($interval);
        $interval = 2 if ($interval *= 2) > 2;
    }

    return $results;
}

# Run one HMC CLI command with the CLIRunner job of the REST API.
sub run_cli {
    my ($self, %options) = @_;

    my $job_id = $self->submit_cli_job(command => $options{command});
    return { status => 'FAILED', rc => '', output => 'cannot find JobID in CLIRunner response' }
        if is_empty($job_id);
    return $self->wait_cli_jobs(job_ids => [ $job_id ])->{$job_id};
}

1;

__END__

=head1 NAME

IBM HMC REST API

=head1 REST API OPTIONS

IBM Hardware Management Console REST API.

=over 8

=item B<--hostname>

HMC hostname or IP address.

=item B<--port>

Port used (default: C<12443>).

=item B<--proto>

Specify https if needed (default: C<https>).

=item B<--api-username>

HMC username (a read-only C<hmcviewer> role is enough, except for the C<vios-errors> mode).

=item B<--api-password>

HMC password.

=item B<--timeout>

Set HTTP timeout in seconds (default: C<50>).

=item B<--job-timeout>

Maximum time in seconds to wait for a REST API job (CLIRunner) to complete (default: C<120>).

=item B<--unknown-http-status>

Define the conditions to match on the HTTP status for the returned status to be UNKNOWN
(default: C<< %{http_code} < 200 or %{http_code} >= 300 >>).
You can use the following variables: C<%{http_code}>

=item B<--warning-http-status>

Define the conditions to match on the HTTP status for the returned status to be WARNING.
You can use the following variables: C<%{http_code}>

=item B<--critical-http-status>

Define the conditions to match on the HTTP status for the returned status to be CRITICAL.
You can use the following variables: C<%{http_code}>

=back

The session token (C<X-API-Session>) is stored in a cache file and reused between checks,
because the HMC limits the number of opened sessions.

=head1 DESCRIPTION

B<custom>.

=cut
