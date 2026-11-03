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
...                 --mode=vios-disks
...                 --hostname=127.0.0.1
...                 --api-username=centreon
...                 --api-password=secret
...                 --proto=http
...                 --statefile-dir=/dev/shm/
...                 --timeout=10
...                 --port=${APIPORT}


*** Test Cases ***
Vios-disks ${tc}
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
    ...    CRITICAL: VIOS 'vios1' [system: Server-9009-42A-SN7860001] disk 'hdisk2' state: failed | 'Server-9009-42A-SN7860001~vios1#vios.disks.detected.count'=4;;;0; 'Server-9009-42A-SN7860001~vios1#vios.disks.failed.count'=1;;;0;4 'Server-9009-42A-SN7860001~vios2#vios.disks.detected.count'=4;;;0; 'Server-9009-42A-SN7860001~vios2#vios.disks.failed.count'=0;;;0;4
    ...    2
    ...    --exclude-disk-name=hdisk2
    ...    OK: All VIOS disks are ok | 'Server-9009-42A-SN7860001~vios1#vios.disks.detected.count'=3;;;0; 'Server-9009-42A-SN7860001~vios1#vios.disks.failed.count'=0;;;0;3 'Server-9009-42A-SN7860001~vios2#vios.disks.detected.count'=4;;;0; 'Server-9009-42A-SN7860001~vios2#vios.disks.failed.count'=0;;;0;4
    ...    3
    ...    --include-vios-name=vios2
    ...    OK: VIOS 'vios2' [system: Server-9009-42A-SN7860001] disks detected: 4, disks failed: 0 - all disks are ok | 'Server-9009-42A-SN7860001~vios2#vios.disks.detected.count'=4;;;0; 'Server-9009-42A-SN7860001~vios2#vios.disks.failed.count'=0;;;0;4
    ...    4
    ...    --critical-disk-status='' --warning-disks-failed=0
    ...    WARNING: VIOS 'vios1' [system: Server-9009-42A-SN7860001] disks failed: 1 | 'Server-9009-42A-SN7860001~vios1#vios.disks.detected.count'=4;;;0; 'Server-9009-42A-SN7860001~vios1#vios.disks.failed.count'=1;0:0;;0;4 'Server-9009-42A-SN7860001~vios2#vios.disks.detected.count'=4;;;0; 'Server-9009-42A-SN7860001~vios2#vios.disks.failed.count'=0;0:0;;0;4
