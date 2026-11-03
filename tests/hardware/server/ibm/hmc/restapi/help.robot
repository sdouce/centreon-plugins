*** Settings ***
Documentation       hardware::server::ibm::hmc::restapi::plugin

Resource            ${CURDIR}${/}..${/}..${/}..${/}..${/}..${/}resources/import.resource

Suite Setup         Ctn Generic Suite Setup
Suite Teardown      Ctn Generic Suite Teardown
Test Timeout        120s


*** Variables ***
${CMD}      ${CENTREON_PLUGINS} --plugin=hardware::server::ibm::hmc::restapi::plugin


*** Test Cases ***
Standard ${tc} - ${mode}
    [Tags]    hardware    ibm    hmc    restapi
    ${command}    Catenate
    ...    ${CMD}
    ...    --mode=${mode}
    ...    --help

    Ctn Run Command And Check Result As Regexp    ${command}    ${expected_result}    flags=IGNORECASE

    Examples:
    ...    tc
    ...    mode
    ...    expected_result
    ...    --
    ...    1
    ...    list-managed-systems
    ...    Mode:\n.*List managed systems
    ...    2
    ...    lpars
    ...    Mode:\n.*logical partitions
    ...    3
    ...    managed-systems
    ...    Mode:\n.*managed systems.*state
    ...    4
    ...    shared-processor-pools
    ...    Mode:\n.*shared processor pools
    ...    5
    ...    system-usage
    ...    Mode:\n.*processor and memory usage
    ...    6
    ...    vios
    ...    Mode:\n.*Virtual I/O Servers.*state
    ...    7
    ...    vios-disks
    ...    Mode:\n.*physical volumes
    ...    8
    ...    vios-errors
    ...    Mode:\n.*error log
    ...    9
    ...    vios-redundancy
    ...    Mode:\n.*redundancy
