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
...                 --mode=list-managed-systems
...                 --hostname=127.0.0.1
...                 --api-username=centreon
...                 --api-password=secret
...                 --proto=http
...                 --statefile-dir=/dev/shm/
...                 --timeout=10
...                 --port=${APIPORT}


*** Test Cases ***
List-managed-systems ${tc}
    [Tags]    hardware    ibm    hmc    restapi
    ${command}    Catenate
    ...    ${CMD}
    ...    ${extra_options}

    Ctn Run Command Without Connector And Check Result As Regexp    ${command}    ${expected_result}

    Examples:    tc    extra_options                    expected_result   --
        ...      1     ${EMPTY}                         ^List managed systems: (\\\\n\\\\[uuid: .*\\\\]){2}\\\\Z
        ...      2     --include-system-name=9080       ^List managed systems: \\\\n\\\\[uuid: b1f2c3d4-0000-3000-8000-000000000002\\\\]\\\\[name: Server-9080-M9S-SN7860002\\\\]\\\\[state: error\\\\].*\\\\Z
        ...      3     --disco-show                     ^\\\\<\\\\?xml version="1.0" encoding="utf-8"\\\\?\\\\>\\\\n\\\\<data\\\\>(\\\\n\\\\s*\\\\<label .*\\\\/\\\\>){2}\\\\n\\\\<\\\\/data\\\\>$
        ...      4     --disco-format                   ^\\\\<\\\\?xml version="1.0" encoding="utf-8"\\\\?\\\\>\\\\n\\\\<data\\\\>(\\\\n\\\\s*\\\\<element\\\\>.*\\\\<\\\\/element\\\\>){6}\\\\n\\\\<\\\\/data\\\\>$
