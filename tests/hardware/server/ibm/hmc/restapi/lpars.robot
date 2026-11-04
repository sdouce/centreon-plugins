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
...                 --mode=lpars
...                 --hostname=127.0.0.1
...                 --api-username=centreon
...                 --api-password=secret
...                 --proto=http
...                 --statefile-dir=/dev/shm/
...                 --timeout=10
...                 --port=${APIPORT}


*** Test Cases ***
Lpars ${tc}
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
    ...    CRITICAL: partition 'lnx01' [system: Server-9009-42A-SN7860001] state: error | 'lpars.detected.count'=4;;;0; 'lpars.running.count'=2;;;0;4
    ...    2
    ...    --include-lpar-name=aix
    ...    OK: Number of partitions detected: 2, running: 1 - All partitions are ok | 'lpars.detected.count'=2;;;0; 'lpars.running.count'=1;;;0;2
    ...    3
    ...    --include-system-name=9009 --exclude-lpar-type=Virtual --critical-lpar-status='' --warning-lpars-running=3:
    ...    WARNING: Number of partitions running: 1 | 'lpars.detected.count'=3;;;0; 'lpars.running.count'=1;3:;;0;3
    ...    4
    ...    --include-lpar-name=aix01 --critical-lpar-status='\\\%{rmcState} ne "active"'
    ...    OK: Number of partitions detected: 1, running: 1 - partition 'aix01' [system: Server-9009-42A-SN7860001] state: running | 'lpars.detected.count'=1;;;0; 'lpars.running.count'=1;;;0;1
