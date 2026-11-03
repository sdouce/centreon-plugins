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
...                 --mode=managed-systems
...                 --hostname=127.0.0.1
...                 --api-username=centreon
...                 --api-password=secret
...                 --proto=http
...                 --statefile-dir=/dev/shm/
...                 --timeout=10
...                 --port=${APIPORT}


*** Test Cases ***
Managed-systems ${tc}
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
    ...    CRITICAL: managed system 'Server-9080-M9S-SN7860002' state: error | 'managedsystems.detected.count'=2;;;0;
    ...    2
    ...    --include-system-name=9009
    ...    OK: Number of managed systems detected: 1 - managed system 'Server-9009-42A-SN7860001' state: operating | 'managedsystems.detected.count'=1;;;0;
    ...    3
    ...    --critical-system-status='' --warning-system-status='\\\%{state} =~ /error/i'
    ...    WARNING: managed system 'Server-9080-M9S-SN7860002' state: error | 'managedsystems.detected.count'=2;;;0;
    ...    4
    ...    --exclude-system-name=.* --critical-systems-detected=1:
    ...    CRITICAL: Number of managed systems detected: 0 | 'managedsystems.detected.count'=0;;1:;0;
