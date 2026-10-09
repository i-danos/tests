# SPDX-License-Identifier: LGPL-2.1-only

*** Settings ***
Documentation   BGP EVPN over VXLAN: does a MAC learned by the control plane reach the
...             data plane and forward?
...
...             The question is narrower than "does EVPN come up". R1 and R2 are bridged
...             through a VXLAN tunnel, so frames R2 floods toward R1 teach R1 R3's MAC from
...             the data path before EVPN exists. A ping afterwards would pass on that entry
...             and prove nothing about EVPN. So this suite clears R1's MAC table, makes FRR
...             reprogram it, requires the only entry present to be one the control plane
...             owns (origin control-plane, which is NTF_EXT_LEARNED on the netlink message),
...             and only then sends traffic, with R1's flood path pointed at an address
...             nothing answers.
...
...             Topology (TOPO=ipsec):
...                R1 dp0s9 --- dp0s3 R2 dp0s8 --- dp0s8 R3
...                VTEP 10.60.60.1      VTEP 10.60.60.2     host 10.61.61.3
...             HowToExecute:  robot EVPN_DANOS.robot

Library         String
Library         ../library/danos_feature.py
Resource        ../keyword/mgmt_keywords.robot

Suite Teardown  Remove EVPN configuration

*** Variables ***
${R1}        192.168.203.155
${R2}        192.168.203.156
${R3}        192.168.203.157
${VNI}       100
${AS}        65000
${MAC3}      ${EMPTY}

*** Test Cases ***
Clear earlier configuration on the three routers
    FOR    ${r}    IN    ${R1}    ${R2}    ${R3}
        Clear Config    ${r}    ${MGMT_restore}    ${MGMT_address}
    END

Configure the two VTEPs and the bridge
    # R1 floods to 10.60.60.99, which nothing answers: any frame that reaches R3
    # from R1 therefore went by a unicast entry, not by flooding.
    Cli Commit    ${R1}
    ...    set interfaces dataplane dp0s9 address 10.60.60.1/24
    ...    set interfaces tunnel tun0 encapsulation vxlan
    ...    set interfaces tunnel tun0 vxlan-id ${VNI}
    ...    set interfaces tunnel tun0 local-ip 10.60.60.1
    ...    set interfaces tunnel tun0 remote-ip 10.60.60.99
    ...    set interfaces bridge br0
    ...    set interfaces bridge br0 address 10.61.61.1/24
    ...    set interfaces tunnel tun0 bridge-group bridge br0
    Cli Commit    ${R2}
    ...    set interfaces dataplane dp0s3 address 10.60.60.2/24
    ...    set interfaces tunnel tun0 encapsulation vxlan
    ...    set interfaces tunnel tun0 vxlan-id ${VNI}
    ...    set interfaces tunnel tun0 local-ip 10.60.60.2
    ...    set interfaces tunnel tun0 remote-ip 10.60.60.1
    ...    set interfaces bridge br0
    ...    set interfaces bridge br0 address 10.61.61.2/24
    ...    set interfaces tunnel tun0 bridge-group bridge br0
    ...    set interfaces dataplane dp0s8 bridge-group bridge br0
    Cli Commit    ${R3}    set interfaces dataplane dp0s8 address 10.61.61.3/24
    Wait Until Keyword Succeeds    60s    3s    Underlay is reachable
    ${mac}=    Interface Mac    ${R3}    dp0s8
    Set Suite Variable    ${MAC3}    ${mac}

The dataplane reports the canonical MAC format
    # An image whose dump still prints "IPAddr" cannot tell a control-plane entry
    # from a learned one, which is the thing measured below. Stop here with that
    # reason rather than fail the next case for a different one.
    Run Keyword And Ignore Error    Ping Received    ${R2}    10.61.61.3
    ${out}=    Vplsh    ${R1}    vxlan macs show
    Should Not Contain    ${out}    IPAddr
    ...    msg=dataplane predates the vxlan_newneigh() address-flag work

R2 learns the host behind it
    ${got}=    Ping Received    ${R2}    10.61.61.3
    Should Be True    ${got} >= 2    R2 could not reach R3 on the bridge (${got} of 3)

Bring up the EVPN session
    Vtysh Config    ${R1}    router bgp ${AS}
    ...    neighbor 10.60.60.2 remote-as ${AS}
    ...    neighbor 10.60.60.2 update-source 10.60.60.1
    ...    address-family l2vpn evpn
    ...    neighbor 10.60.60.2 activate
    ...    advertise-all-vni
    Vtysh Config    ${R2}    router bgp ${AS}
    ...    neighbor 10.60.60.1 remote-as ${AS}
    ...    neighbor 10.60.60.1 update-source 10.60.60.2
    ...    address-family l2vpn evpn
    ...    neighbor 10.60.60.1 activate
    ...    advertise-all-vni
    Wait Until Keyword Succeeds    120s    5s    EVPN session is established    ${R1}
    Wait Until Keyword Succeeds    120s    5s    EVPN session is established    ${R2}

Zebra learns the VNI from the DANOS VXLAN interface
    ${out}=    Vtysh    ${R1}    show evpn vni
    Should Match Regexp    ${out}    (?m)^\\s*${VNI}\\s+L2
    ${out}=    Vtysh    ${R2}    show evpn vni
    Should Match Regexp    ${out}    (?m)^\\s*${VNI}\\s+L2

The remote MAC arrives from the control plane
    # Clearing the table removes the learned entry along with any netlink one, so
    # make FRR resend. What must be there afterwards is the control-plane entry.
    Vplsh    ${R1}    vxlan macs clear tun0
    Vtysh    ${R1}    clear bgp l2vpn evpn *
    Wait Until Keyword Succeeds    120s    5s    MAC 3 is held by the control plane

The control-plane entry forwards
    ${before}=    Vxlan Out Discards    ${R1}
    # A static neighbour so the first frame is unicast: an ARP would be flooded,
    # and the flood path is the one pointed at nothing.
    Router Run    ${R1}    sudo ip neigh replace 10.61.61.3 lladdr ${MAC3} dev br0
    ${got}=    Ping Received    ${R1}    10.61.61.3
    ${after}=    Vxlan Out Discards    ${R1}
    Should Be True    ${got} >= 2    R1 -> R3 over the EVPN entry: ${got} of 3
    Should Be Equal As Integers    ${before}    ${after}
    ...    msg=vxlan_output() dropped something during the run (OutDiscards ${before} -> ${after})

The data path does not take the entry over
    ${e}=    Evpn Mac Entry    ${R1}    ${MAC3}
    Should Not Be Equal    ${e}    ${None}    the entry disappeared after the traffic
    Should Be Equal    ${e['origin']}    control-plane
    ...    msg=replies over the tunnel took a control-plane MAC away from BGP

*** Keywords ***
Underlay is reachable
    ${got}=    Ping Received    ${R1}    10.60.60.2    2
    Should Be True    ${got} >= 1    the VTEPs cannot reach each other

EVPN session is established
    [Arguments]    ${router}
    ${out}=    Vtysh    ${router}    show bgp l2vpn evpn summary
    Should Match Regexp    ${out}    (?m)^10\\.60\\.60\\.\\d+\\s+4\\s+\\d+\\s+\\d+\\s+\\d+\\s+\\d+\\s+\\d+\\s+\\d+\\s+\\S+\\s+\\d+
    Should Not Contain    ${out}    Active
    Should Not Contain    ${out}    Idle

MAC 3 is held by the control plane
    ${e}=    Evpn Mac Entry    ${R1}    ${MAC3}
    Should Not Be Equal    ${e}    ${None}    no entry for ${MAC3} yet
    Should Be Equal    ${e['origin']}    control-plane
    Should Be Equal    ${e['remote_ip']}    10.60.60.2

Remove EVPN configuration
    FOR    ${r}    IN    ${R1}    ${R2}
        Vtysh Config    ${r}    no router bgp ${AS}
    END
    Cli Commit    ${R1}    delete interfaces tunnel tun0
    ...    delete interfaces bridge br0
    ...    delete interfaces dataplane dp0s9 address 10.60.60.1/24
    Cli Commit    ${R2}    delete interfaces dataplane dp0s8 bridge-group
    ...    delete interfaces tunnel tun0
    ...    delete interfaces bridge br0
    ...    delete interfaces dataplane dp0s3 address 10.60.60.2/24
    Cli Commit    ${R3}    delete interfaces dataplane dp0s8 address 10.61.61.3/24
