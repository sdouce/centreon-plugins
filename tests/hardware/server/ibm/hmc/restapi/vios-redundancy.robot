*** Settings ***
Documentation       hardware::server::ibm::hmc::restapi::plugin

Resource            ${CURDIR}${/}..${/}..${/}..${/}..${/}..${/}resources/import.resource

Suite Setup         Start Mockoon    ${MOCKOON_JSON}
Suite Teardown      Stop Mockoon
Test Timeout        120s

*** Variables ***
${MOCKOON_JSON}     ${CURDIR}${/}mockoon.json

${CMD}              ${CENTREON_PLUGINS}
...                 --plugin=hardware::server::ibm::hmc::restapi::plugin
...                 --mode=vios-redundancy
...                 --hostname=127.0.0.1
...                 --api-username=centreon
...                 --api-password=secret
...                 --proto=http
...                 --statefile-dir=/dev/shm/
...                 --timeout=10
...                 --port=${APIPORT}


*** Test Cases ***
Vios-redundancy ${tc}
    [Tags]    hardware    ibm    hmc    restapi

    ${command}    Catenate
    ...    ${CMD}
    ...    ${extra_options}

    Ctn Run Command And Check Result As Strings    ${command}    ${expected_result}

    Examples:
    ...    tc
    ...    extra_options
    ...    expected_result
    ...    --
    ...    1
    ...    ${EMPTY}
    ...    WARNING: partition 'aix02' [system: Server-9009-42A-SN7860001] vfc 'npiv' running VIOS paths: 1/2 [vios1, vios2], configuration: no physical port on VIOS vios2 - partition 'aix02' [system: Server-9009-42A-SN7860001] vscsi 'hdisk3' configuration: reserve policy vios1=SinglePath, vios2=SinglePath | 'vios.client.devices.detected.count'=5;;;0; 'vios.client.devices.nonredundant.count'=1;;;0;5
    ...    2
    ...    --include-lpar-name=aix01
    ...    OK: Number of client virtual devices non redundant: 0 - All client virtual devices are redundant | 'vios.client.devices.detected.count'=3;;;0; 'vios.client.devices.nonredundant.count'=0;;;0;3
    ...    3
    ...    --include-device-type=vscsi
    ...    WARNING: partition 'aix02' [system: Server-9009-42A-SN7860001] vscsi 'hdisk3' configuration: reserve policy vios1=SinglePath, vios2=SinglePath | 'vios.client.devices.detected.count'=3;;;0; 'vios.client.devices.nonredundant.count'=0;;;0;3
    ...    4
    ...    --include-lpar-name=aix02 --include-device-type=vfc --warning-configuration-status='' --critical-redundancy-status='\\\%{viosRunning} < 2'
    ...    CRITICAL: partition 'aix02' [system: Server-9009-42A-SN7860001] vfc 'npiv' running VIOS paths: 1/2 [vios1, vios2] | 'vios.client.devices.detected.count'=1;;;0; 'vios.client.devices.nonredundant.count'=1;;;0;1
