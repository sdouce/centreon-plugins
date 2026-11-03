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
    ...    WARNING: managed system 'Server-9009-42A-SN7860001' VIOS 'vios2' RMC state: inactive | 'Server-9009-42A-SN7860001#vios.running.count'=2;;2:;0;2
    ...    2
    ...    --warning-vios-rmc-status=''
    ...    OK: managed system 'Server-9009-42A-SN7860001' VIOS running: 2 - all VIOS are ok | 'Server-9009-42A-SN7860001#vios.running.count'=2;;2:;0;2
    ...    3
    ...    --include-vios-name=vios1 --warning-vios-rmc-status='' --critical-vios-running=2:
    ...    CRITICAL: managed system 'Server-9009-42A-SN7860001' VIOS running: 1 | 'Server-9009-42A-SN7860001#vios.running.count'=1;;2:;0;1
    ...    4
    ...    --exclude-system-name=9009
    ...    UNKNOWN: No VIOS found. 
