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
...                 --mode=vios-errors
...                 --hostname=127.0.0.1
...                 --api-username=centreon
...                 --api-password=secret
...                 --proto=http
...                 --statefile-dir=/dev/shm/
...                 --timeout=10
...                 --port=${APIPORT}


*** Test Cases ***
Vios-errors ${tc}
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
    ...    --retention=0
    ...    CRITICAL: VIOS 'vios1' [system: Server-9009-42A-SN7860001] errors: 2 [last: 2026-11-03 10:45 hdisk2 PATH HAS FAILED] | 'Server-9009-42A-SN7860001~vios1#vios.errors.count'=2;;0:0;0; 'Server-9009-42A-SN7860001~vios2#vios.errors.count'=0;;0:0;0;
    ...    2
    ...    --retention=0 --exclude-error=hdisk2
    ...    CRITICAL: VIOS 'vios1' [system: Server-9009-42A-SN7860001] errors: 1 [last: 2026-11-02 22:10 fcs0 ADAPTER ERROR] | 'Server-9009-42A-SN7860001~vios1#vios.errors.count'=1;;0:0;0; 'Server-9009-42A-SN7860001~vios2#vios.errors.count'=0;;0:0;0;
    ...    3
    ...    --retention=0 --error-type=PT --error-class=H
    ...    CRITICAL: VIOS 'vios1' [system: Server-9009-42A-SN7860001] errors: 3 [last: 2026-11-03 10:45 hdisk2 PATH HAS FAILED] | 'Server-9009-42A-SN7860001~vios1#vios.errors.count'=3;;0:0;0; 'Server-9009-42A-SN7860001~vios2#vios.errors.count'=0;;0:0;0;
    ...    4
    ...    --retention=0 --include-vios-name=vios2
    ...    OK: VIOS 'vios2' [system: Server-9009-42A-SN7860001] errlog command status: COMPLETED_OK, errors: 0 | 'Server-9009-42A-SN7860001~vios2#vios.errors.count'=0;;0:0;0;
    ...    5
    ...    --retention=0 --critical-errors=5 --warning-errors=1
    ...    WARNING: VIOS 'vios1' [system: Server-9009-42A-SN7860001] errors: 2 [last: 2026-11-03 10:45 hdisk2 PATH HAS FAILED] | 'Server-9009-42A-SN7860001~vios1#vios.errors.count'=2;0:1;0:5;0; 'Server-9009-42A-SN7860001~vios2#vios.errors.count'=0;0:1;0:5;0;
