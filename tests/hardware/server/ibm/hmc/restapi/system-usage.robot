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
...                 --mode=system-usage
...                 --hostname=127.0.0.1
...                 --api-username=centreon
...                 --api-password=secret
...                 --proto=http
...                 --statefile-dir=/dev/shm/
...                 --timeout=10
...                 --port=${APIPORT}


*** Test Cases ***
System-usage ${tc}
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
    ...    OK: managed system 'Server-9009-42A-SN7860001' cpu usage: 67.19 %, memory total: 1.00 TB assigned to partitions: 896.00 GB (87.50%) available: 128.00 GB (12.50%) | 'Server-9009-42A-SN7860001#system.cpu.utilization.percentage'=67.19%;;;0;100 'Server-9009-42A-SN7860001#system.cpu.utilized.count'=21.500;;;0;32 'Server-9009-42A-SN7860001#system.memory.assigned.bytes'=962072674304B;;;0;1099511627776 'Server-9009-42A-SN7860001#system.memory.assigned.percentage'=87.50%;;;0;100
    ...    2
    ...    --warning-cpu-utilization=60 --critical-memory-assigned-prct=80
    ...    CRITICAL: managed system 'Server-9009-42A-SN7860001' cpu usage: 67.19 %, memory total: 1.00 TB assigned to partitions: 896.00 GB (87.50%) available: 128.00 GB (12.50%) | 'Server-9009-42A-SN7860001#system.cpu.utilization.percentage'=67.19%;0:60;;0;100 'Server-9009-42A-SN7860001#system.cpu.utilized.count'=21.500;;;0;32 'Server-9009-42A-SN7860001#system.memory.assigned.bytes'=962072674304B;;;0;1099511627776 'Server-9009-42A-SN7860001#system.memory.assigned.percentage'=87.50%;;0:80;0;100
    ...    3
    ...    --exclude-system-name=9009
    ...    UNKNOWN: No performance data found (check that PCM data collection is enabled on the managed systems). 
