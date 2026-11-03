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
...                 --mode=shared-processor-pools
...                 --hostname=127.0.0.1
...                 --api-username=centreon
...                 --api-password=secret
...                 --proto=http
...                 --statefile-dir=/dev/shm/
...                 --timeout=10
...                 --port=${APIPORT}


*** Test Cases ***
Shared-processor-pools ${tc}
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
    ...    OK: All shared processor pools are ok | 'Server-9009-42A-SN7860001~DefaultPool#pool.cpu.utilization.percentage'=40.00%;;;0;100 'Server-9009-42A-SN7860001~DefaultPool#pool.cpu.utilized.count'=6.400;;;0;16 'Server-9009-42A-SN7860001~OraclePool#pool.cpu.utilization.percentage'=95.00%;;;0;100 'Server-9009-42A-SN7860001~OraclePool#pool.cpu.utilized.count'=7.600;;;0;8
    ...    2
    ...    --warning-pool-utilization=90
    ...    WARNING: shared processor pool 'OraclePool' [system: Server-9009-42A-SN7860001] usage: 95.00 % | 'Server-9009-42A-SN7860001~DefaultPool#pool.cpu.utilization.percentage'=40.00%;0:90;;0;100 'Server-9009-42A-SN7860001~DefaultPool#pool.cpu.utilized.count'=6.400;;;0;16 'Server-9009-42A-SN7860001~OraclePool#pool.cpu.utilization.percentage'=95.00%;0:90;;0;100 'Server-9009-42A-SN7860001~OraclePool#pool.cpu.utilized.count'=7.600;;;0;8
    ...    3
    ...    --include-pool-name=Default --critical-pool-utilized=6
    ...    CRITICAL: shared processor pool 'DefaultPool' [system: Server-9009-42A-SN7860001] processor units used: 6.40 | 'Server-9009-42A-SN7860001~DefaultPool#pool.cpu.utilization.percentage'=40.00%;;;0;100 'Server-9009-42A-SN7860001~DefaultPool#pool.cpu.utilized.count'=6.400;;0:6;0;16
