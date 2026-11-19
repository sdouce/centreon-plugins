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
...                 --mode=vios
...                 --hostname=127.0.0.1
...                 --api-username=centreon
...                 --api-password=secret
...                 --proto=http
...                 --statefile-dir=/dev/shm/
...                 --timeout=10
...                 --port=${APIPORT}


*** Test Cases ***
Vios ${tc}
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
    ...    CRITICAL: managed system 'Server-9080-M9S-SN7860002' state: error WARNING: managed system 'Server-9009-42A-SN7860001' VIOS 'vios2' RMC state: inactive | 'Server-9009-42A-SN7860001#vios.running.count'=2;;2:;0;2
    ...    2
    ...    --warning-vios-rmc-status=''
    ...    CRITICAL: managed system 'Server-9080-M9S-SN7860002' state: error | 'Server-9009-42A-SN7860001#vios.running.count'=2;;2:;0;2
    ...    3
    ...    --include-vios-name=vios1 --warning-vios-rmc-status='' --critical-vios-running=2:
    ...    CRITICAL: managed system 'Server-9009-42A-SN7860001' VIOS running: 1 | 'Server-9009-42A-SN7860001#vios.running.count'=1;;2:;0;1
    ...    4
    ...    --exclude-system-name=9009
    ...    CRITICAL: managed system 'Server-9080-M9S-SN7860002' state: error
    ...    5
    ...    --exclude-system-name=.*
    ...    UNKNOWN: No VIOS found.
    ...    6
    ...    --critical-system-status='\\\%{state} !~ /^(?:operating|error)$/i' --warning-vios-rmc-status=''
    ...    OK: All VIOS are ok | 'Server-9009-42A-SN7860001#vios.running.count'=2;;2:;0;2
    ...    7
    ...    --critical-system-status='' --warning-system-status='\\\%{state} =~ /error/i' --include-system-name=9080
    ...    WARNING: managed system 'Server-9080-M9S-SN7860002' state: error
