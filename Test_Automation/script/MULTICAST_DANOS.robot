# SPDX-License-Identifier: LGPL-2.1-only

*** Settings ***
Documentation   Multicast: protocol state and packets crossing the data plane.
...
...             The instrument is the data plane's own tables (multicast mif / mif6 and
...             fcstat / fcstat6), not "show ip mroute": a control plane that believes it
...             forwards says nothing about whether packets crossed the box. Counters are
...             read before and after a burst, and the burst itself is asserted to have
...             been sent, because zero counters are exactly what a broken path looks like.
...
...             Every router is configured from nothing here, addresses and OSPF
...             included. A run that leaned on an earlier suite's addresses passed on a
...             router whose multicast interface table held only pimreg.
...
...             Topology (TOPO=fw):
...                R1 dp0s9 --- dp0s9 R2 dp0s10 --- dp0s10 R3 dp0s9
...                source              transit              receiver
...             IPv4 SSM needs no RP; IPv6 uses a static RP on R2's loopback and OSPFv3.
...             HowToExecute:  robot MULTICAST_DANOS.robot

Library         String
Library         ../library/danos_feature.py
Resource        ../keyword/mgmt_keywords.robot

Suite Teardown  Remove multicast configuration

*** Variables ***
${R1}            192.168.203.155
${R2}            192.168.203.156
${R3}            192.168.203.157
${SSM_GROUP}     232.1.1.1
${SSM_SOURCE}    65.1.1.2
${V6_GROUP}      ff0e::1
${COUNT}         3000
# Packets that must cross, as a share of ${COUNT}. The sender paces at 1 ms and a
# QEMU guest drops some; the point is that the path forwards, not its loss rate.
${MIN_SHARE}     0.5

*** Test Cases ***
Clear earlier configuration on the three routers
    FOR    ${r}    IN    ${R1}    ${R2}    ${R3}
        Clear Config    ${r}    ${MGMT_restore}    ${MGMT_address}
    END

Configure IPv4 SSM with OSPF on all three routers
    Cli Commit    ${R1}
    ...    set interfaces dataplane dp0s9 address 65.1.1.2/24
    ...    set interfaces loopback lo1 address 1.1.1.1/32
    ...    set protocols ospf area 0 network 65.1.1.0/24
    ...    set protocols ospf area 0 network 1.1.1.1/32
    ...    set protocols ospf parameters router-id 1.1.1.1
    ...    set policy route prefix-list SSM-RANGE rule 1 action permit
    ...    set policy route prefix-list SSM-RANGE rule 1 prefix 232.0.0.0/8
    ...    set protocols pim ssm prefix-list SSM-RANGE
    ...    set interfaces dataplane dp0s9 ip pim
    ...    set interfaces loopback lo1 ip pim
    Cli Commit    ${R2}
    ...    set interfaces dataplane dp0s9 address 65.1.1.3/24
    ...    set interfaces dataplane dp0s10 address 66.1.1.3/24
    ...    set interfaces loopback lo1 address 2.2.2.2/32
    ...    set protocols ospf area 0 network 65.1.1.0/24
    ...    set protocols ospf area 0 network 66.1.1.0/24
    ...    set protocols ospf area 0 network 2.2.2.2/32
    ...    set protocols ospf parameters router-id 2.2.2.2
    ...    set interfaces dataplane dp0s9 ip pim
    ...    set interfaces dataplane dp0s10 ip pim
    ...    set interfaces loopback lo1 ip pim
    ...    set policy route prefix-list SSM-RANGE rule 1 action permit
    ...    set policy route prefix-list SSM-RANGE rule 1 prefix 232.0.0.0/8
    ...    set protocols pim ssm prefix-list SSM-RANGE
    Cli Commit    ${R3}
    ...    set interfaces dataplane dp0s10 address 66.1.1.2/24
    ...    set interfaces dataplane dp0s9 address 172.16.1.2/24
    ...    set interfaces loopback lo1 address 3.3.3.3/32
    ...    set protocols ospf area 0 network 66.1.1.0/24
    ...    set protocols ospf area 0 network 3.3.3.3/32
    ...    set protocols ospf parameters router-id 3.3.3.3
    ...    set interfaces dataplane dp0s10 ip pim
    ...    set interfaces dataplane dp0s9 ip pim
    ...    set interfaces loopback lo1 ip pim
    ...    set policy route prefix-list SSM-RANGE rule 1 action permit
    ...    set policy route prefix-list SSM-RANGE rule 1 prefix 232.0.0.0/8
    ...    set protocols pim ssm prefix-list SSM-RANGE
    ...    set interfaces dataplane dp0s9 ip igmp
    ...    set interfaces dataplane dp0s9 ip igmp version 3
    ...    set interfaces dataplane dp0s9 ip igmp join-group ${SSM_GROUP} source ${SSM_SOURCE}

PIM neighbours and the SSM tree form
    Wait Until Keyword Succeeds    150s    5s    Output contains    ${R2}
    ...    show ip pim neighbor    65.1.1.2
    Wait Until Keyword Succeeds    150s    5s    Output contains    ${R2}
    ...    show ip pim neighbor    66.1.1.2
    Wait Until Keyword Succeeds    90s    5s    Output contains    ${R3}
    ...    show ip igmp join    ${SSM_GROUP}
    Wait Until Keyword Succeeds    90s    5s    Output contains    ${R2}
    ...    show ip mroute    ${SSM_GROUP}

IPv4 SSM packets cross the transit router
    Warm up the forwarding entry    ${R1}    ${R2}    dp0s10    mif    v4
    ${in0}=    Mif In     ${R2}    dp0s9
    ${out0}=   Mif Out    ${R2}    dp0s10
    ${r3in0}=  Mif In     ${R3}    dp0s10
    ${sent}=   Send Multicast V4    ${R1}    ${SSM_GROUP}    ${SSM_SOURCE}    ${COUNT}
    Sleep    3s
    ${in1}=    Mif In     ${R2}    dp0s9
    ${out1}=   Mif Out    ${R2}    dp0s10
    ${r3in1}=  Mif In     ${R3}    dp0s10
    ${min}=    Evaluate    int(${COUNT} * ${MIN_SHARE})
    Should Be True    ${in1} - ${in0} >= ${min}    R2 received ${in1}-${in0} of ${COUNT}
    Should Be True    ${out1} - ${out0} >= ${min}    R2 forwarded ${out1}-${out0} of ${COUNT}
    Should Be True    ${r3in1} - ${r3in0} >= ${min}    R3 received ${r3in1}-${r3in0} of ${COUNT}

The SSM forwarding entry counts the burst
    ${n}=    Fcstat Packets    ${R2}    ${SSM_GROUP}
    ${min}=    Evaluate    int(${COUNT} * ${MIN_SHARE})
    Should Be True    ${n} >= ${min}    forwarding-cache entry counted ${n} packets

Configure IPv6 PIM with a static RP and OSPFv3
    Cli Commit    ${R1}
    ...    set interfaces dataplane dp0s9 address 2001:db8:65::2/64
    ...    set interfaces loopback lo1 address 2001:db8::1/128
    ...    set protocols ospfv3 area 0 interface dp0s9
    ...    set protocols ospfv3 area 0 interface lo1
    ...    set interfaces dataplane dp0s9 ipv6 pim
    ...    set interfaces loopback lo1 ipv6 pim
    ...    set protocols pim6 rp 2001:db8::2 group ff00::/8
    Cli Commit    ${R2}
    ...    set interfaces dataplane dp0s9 address 2001:db8:65::3/64
    ...    set interfaces dataplane dp0s10 address 2001:db8:66::3/64
    ...    set interfaces loopback lo1 address 2001:db8::2/128
    ...    set protocols ospfv3 area 0 interface dp0s9
    ...    set protocols ospfv3 area 0 interface dp0s10
    ...    set protocols ospfv3 area 0 interface lo1
    ...    set interfaces dataplane dp0s9 ipv6 pim
    ...    set interfaces dataplane dp0s10 ipv6 pim
    ...    set interfaces loopback lo1 ipv6 pim
    ...    set protocols pim6 rp 2001:db8::2 group ff00::/8
    Cli Commit    ${R3}
    ...    set interfaces dataplane dp0s10 address 2001:db8:66::2/64
    ...    set interfaces dataplane dp0s9 address 2001:db8:72::2/64
    ...    set interfaces loopback lo1 address 2001:db8::3/128
    ...    set protocols ospfv3 area 0 interface dp0s10
    ...    set protocols ospfv3 area 0 interface dp0s9
    ...    set protocols ospfv3 area 0 interface lo1
    ...    set interfaces dataplane dp0s10 ipv6 pim
    ...    set interfaces dataplane dp0s9 ipv6 pim
    ...    set interfaces loopback lo1 ipv6 pim
    ...    set interfaces dataplane dp0s9 ipv6 mld
    ...    set interfaces dataplane dp0s9 ipv6 mld version 2
    ...    set interfaces dataplane dp0s9 ipv6 mld join-group ${V6_GROUP}
    ...    set protocols pim6 rp 2001:db8::2 group ff00::/8

IPv6 reaches the RP and PIM6 neighbours form
    Wait Until Keyword Succeeds    150s    5s    Output contains    ${R1}
    ...    show ipv6 route 2001:db8::2/128    2001:db8::2/128
    Wait Until Keyword Succeeds    150s    5s    Output contains    ${R2}
    ...    show ipv6 pim neighbor    fe80::
    Wait Until Keyword Succeeds    90s    5s    Output contains    ${R3}
    ...    show ipv6 mld joins    ${V6_GROUP}

IPv6 multicast packets cross the transit router
    Warm up the forwarding entry    ${R1}    ${R2}    dp0s10    mif6    v6
    ${in0}=    Mif In     ${R2}    dp0s9     mif6
    ${out0}=   Mif Out    ${R2}    dp0s10    mif6
    ${r3in0}=  Mif In     ${R3}    dp0s10    mif6
    ${sent}=   Send Multicast V6    ${R1}    ${V6_GROUP}    dp0s9    ${COUNT}
    Sleep    3s
    ${in1}=    Mif In     ${R2}    dp0s9     mif6
    ${out1}=   Mif Out    ${R2}    dp0s10    mif6
    ${r3in1}=  Mif In     ${R3}    dp0s10    mif6
    ${min}=    Evaluate    int(${COUNT} * ${MIN_SHARE})
    Should Be True    ${in1} - ${in0} >= ${min}    R2 received ${in1}-${in0} of ${COUNT}
    Should Be True    ${out1} - ${out0} >= ${min}    R2 forwarded ${out1}-${out0} of ${COUNT}
    Should Be True    ${r3in1} - ${r3in0} >= ${min}    R3 received ${r3in1}-${r3in0} of ${COUNT}

*** Keywords ***
Warm up the forwarding entry
    [Documentation]    The first packets of a flow miss the forwarding cache and are
    ...                handled by the slow path until the entry is installed. On a
    ...                slow runner that took long enough to swallow two thirds of a
    ...                3000-packet burst (R2 received 2998, forwarded 1042), which
    ...                measured the install time and not the forwarding. Send a short
    ...                burst, wait until the transit router forwards, then measure.
    ...                The install latency itself is not asserted here.
    [Arguments]    ${source}    ${transit}    ${out_if}    ${family}    ${ver}
    Wait Until Keyword Succeeds    90s    1s    Send a short burst and check forwarding
    ...    ${source}    ${transit}    ${out_if}    ${family}    ${ver}
    Sleep    2s

Send a short burst and check forwarding
    [Arguments]    ${source}    ${transit}    ${out_if}    ${family}    ${ver}
    IF    '${ver}' == 'v4'
        Send Multicast V4    ${source}    ${SSM_GROUP}    ${SSM_SOURCE}    200
    ELSE
        Send Multicast V6    ${source}    ${V6_GROUP}    dp0s9    200
    END
    Sleep    1s
    Transit router forwards    ${transit}    ${out_if}    ${family}

Transit router forwards
    [Arguments]    ${router}    ${out_if}    ${family}
    ${n}=    Mif Out    ${router}    ${out_if}    ${family}
    Should Be True    ${n} > 0    nothing forwarded on ${out_if} yet

Output contains
    [Arguments]    ${router}    ${command}    ${needle}
    ${out}=    Vtysh    ${router}    ${command}
    Should Contain    ${out}    ${needle}

Remove multicast configuration
    FOR    ${r}    IN    ${R1}    ${R2}    ${R3}
        Clear Config    ${r}    ${MGMT_restore}    ${MGMT_address}
    END
