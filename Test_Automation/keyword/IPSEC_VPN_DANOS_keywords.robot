# * Copyright (c) 2020-2021, Happiest Minds Technologies Limited Intellectual Property. All rights reserved.
# * All rights reserved.
# *
# * SPDX-License-Identifier: LGPL-2.1-only
*** Settings ***
#Variables         ../variable/IPSEC_VPN_DANOS_Variables.py
Library           SSHLibrary
Library           String
Library           Collections
Library           ../library/danos_cli.py

*** Variables ***
${vpnif}   .spathintf
${dest1}   ${R1H1interfaceIP}
${dest2}   ${R3H2interfaceIP}

*** Keywords ***
Access check and enable vymgmt support
    FOR  ${vm}  IN    ${R1}    ${R2}    ${R3}
        Log    Access check and enable vymgmt support on ${vm}
        ${id}    Open Connection   ${vm}    prompt=$    alias=${vm}    timeout=15
        Login   ${user}    ${pa}
        Execute Command   touch .hushlogin
        Write    show version
        ${o}    Read Until    $
        Log    ${o}
        # Was "danos-", which matched the 2105 image name and nothing in
        # 2608: the image is i-danos and "show version" never carried the
        # old string. BGP_DANOS_keywords.robot already asserts on the
        # release banner, which is stable across image names.
        Should Contain    ${o}    DANOS:Shipping:${RELEASE}
        Log    Access to ${vm} is successful and enabled vymgmt support
        Close All Connections

    END
Clear configurations on the topology
    FOR  ${vm}  IN    ${R1}    ${R2}    ${R3}
        Log    Clear configurations on ${vm}
        ${id}    Open Connection   ${vm}    prompt=$    alias=${vm}    timeout=15
        Login   ${user}    ${pa}
        Write    configure
        ${o}    Read Until    \#
        Write    delete interfaces
        ${o}    Read Until    \#
        Write    delete security vpn ipsec
        ${o}    Read Until    \#
        Write    delete protocols ospf
        ${o}    Read Until    \#
        Write    commit
        ${o}    Read Until    \#
        Close All Connections
    END

ShowService
    [Arguments]    ${arg1}    ${arg2}    ${arg3}    ${arg4}
    Open Connection   ${arg1}    prompt=$    alias=${arg1}    timeout=15
    Login   ${arg2}    ${arg3}
    Write    configure
    ${o}    Read Until    \#
    Write    ${arg4}
    ${o}    Read Until    \#
    Close All Connections
    ${o2}    Split String    ${o}    "\n"
    [Return]    ${o2}

Configure R1 interfaces
    Log    Configure R1 interfaces
    danos_cli.config_ipsecvpn    ${R1}   ${user}    ${pa}    ${R1_interface_config}

Configure R2 interfaces
    Log    Configure R2 interfaces
    danos_cli.config_ipsecvpn    ${R2}   ${user}    ${pa}    ${R2_interface_config}

Configure R3 interfaces
    Log    Configure R3 interfaces
    danos_cli.config_ipsecvpn    ${R3}   ${user}    ${pa}    ${R3_interface_config}

Configure routing protocol on R1
    Log    Configure OSPF on R1
    danos_cli.config_ipsecvpn    ${R1}   ${user}    ${pa}    ${R1_protocol_config}

Configure routing protocol on R2
    Log    Configure OSPF on R2
    danos_cli.config_ipsecvpn    ${R2}   ${user}    ${pa}    ${R2_protocol_config}

Configure routing protocol on R3
    Log    Configure OSPF on R3
    danos_cli.config_ipsecvpn    ${R3}   ${user}    ${pa}    ${R3_protocol_config}

Configure R1 interface tunnel
    Log    Configure R1 interface tunnel
    danos_cli.config_ipsecvpn    ${R1}   ${user}    ${pa}    ${R1_interface_tunnel_config}

Configure R3 interface tunnel
    Log    Configure R3 interface tunnel
    danos_cli.config_ipsecvpn    ${R3}   ${user}    ${pa}    ${R3_interface_tunnel_config}

Configure R1 IPSEC VPN
    Log    Configure R1 IPSEC VPN
    danos_cli.config_ipsecvpn    ${R1}   ${user}    ${pa}    ${R1_ipsec_vpn_config}

Configure R3 IPSEC VPN
    Log    Configure R3 IPSEC VPN
    danos_cli.config_ipsecvpn    ${R3}   ${user}    ${pa}    ${R3_ipsec_vpn_config}

Verify connectivity from R1
    FOR  ${ip}  IN  @{R1_pingcheck}
        Log    Verify pinging interface IPs from ${ip}
        ${c1}    Catenate    ping -c1     ${ip}
        ShowService    ${R1}   ${user}    ${pa}    ${c1}
    # This is not working from  jenkins and hence using ShowService method
    #\    danos_cli.config_show_ipsecvpn    ${R1}   ${user}    ${pa}    ${c1}
        ${cmd}    Catenate    ping -c1     ${ip}
        ${output}    ShowService    ${R1}   ${user}    ${pa}    ${c1}
    #\    ${output}    danos_cli.config_show_ipsecvpn    ${R1}   ${user}    ${pa}    ${cmd}
        danos_cli.pr    ${output}
        ${o}    Evaluate    ''.join(${output})
        Should Not Contain    ${o}    100%

    END
Verify connectivity from R2
    FOR  ${ip}  IN  @{R2_pingcheck}
        Log    Verify pinging interface IPs from ${ip}
        ${c1}    Catenate    ping -c1     ${ip}
        ShowService    ${R2}   ${user}    ${pa}    ${c1}
        ${cmd}    Catenate    ping -c1     ${ip}
        ${output}    ShowService    ${R2}   ${user}    ${pa}    ${c1}
        danos_cli.pr    ${output}
        ${o}    Evaluate    ''.join(${output})
        Should Not Contain    ${o}    100%

    END
Verify connectivity from R3
    FOR  ${ip}  IN  @{R3_pingcheck}
        Log    Verify pinging interface IPs from ${ip}
        ${c1}    Catenate    ping -c1     ${ip}
        ShowService    ${R3}   ${user}    ${pa}    ${c1}
        ${cmd}    Catenate    ping -c1     ${ip}
        ${output}    ShowService    ${R3}   ${user}    ${pa}    ${c1}
        danos_cli.pr    ${output}
        ${o}    Evaluate    ''.join(${output})
        Should Not Contain    ${o}    100%
    END

Verify E2E reachability from R1
    Log    Verify E2E reachability from R1
    ${cmd}    Catenate    ping -c2     ${R1_e2e_pingcheck_ip}
    ${output}    danos_cli.config_show_ipsecvpn    ${R1}   ${user}    ${pa}    ${cmd}
    danos_cli.pr    ${output}
    ${o}    Evaluate    ''.join(${output})
    Should Not Contain    ${o}    100%

Verify E2E reachability from R3
    Log    Verify E2E reachability from R3
    ${cmd}    Catenate    ping -c2     ${R3_e2e_pingcheck_ip}
    ${output}    danos_cli.config_show_ipsecvpn    ${R3}   ${user}    ${pa}    ${cmd}
    danos_cli.pr    ${output}
    ${o}    Evaluate    ''.join(${output})
    Should Not Contain    ${o}    100%

Send traffic and validate it is received
    Log   Send ICMP traffic from ${dest1} to ${dest2} and confirm it arrives
    # Was a tcpdump on R3's .spathintf asserting both addresses appear. That
    # interface is the dataplane's slow path; traffic through an established
    # tunnel takes the fast path and never shows up there, so the capture came
    # back empty for a tunnel that was working. Same reason the encryption
    # check below moved off tcpdump.
    #
    # R3's inbound SA counter answers the question directly: it advances only
    # when R3 decrypts packets that reached it.
    ${before}    danos_cli.ipsec_sa_packets    ${R3}    ${user}    ${pa}

    danos_cli.sendping    ${R1}   ${user}    ${pa}    ${dest2}
    Sleep    8s

    ${after}    danos_cli.ipsec_sa_packets    ${R3}    ${user}    ${pa}
    Log    R3 SA packets ${before} -> ${after}
    Should Be True    ${after} > ${before}    no traffic reached R3 through the tunnel

Validate VPN traffic is encrypted in the network
    Log   Verify the dataplane SAs carry the traffic
    # This used to run tcpdump on each router and assert on ESP. That cannot
    # work here: the interfaces belong to the DPDK dataplane, so the kernel --
    # and tcpdump with it -- only sees the cleartext copy handed up to it,
    # while the ciphertext goes straight out of the physical port. All three
    # routers captured plaintext ICMP and zero ESP while the tunnel was
    # carrying traffic correctly, so the check failed for a working tunnel.
    #
    # The SA counters do distinguish the two cases: they advance only when
    # packets are encrypted or decrypted.
    ${before1}    danos_cli.ipsec_sa_packets    ${R1}    ${user}    ${pa}
    ${before3}    danos_cli.ipsec_sa_packets    ${R3}    ${user}    ${pa}

    danos_cli.sendping    ${R1}   ${user}    ${pa}    ${dest2}
    Sleep    8s

    ${after1}    danos_cli.ipsec_sa_packets    ${R1}    ${user}    ${pa}
    ${after3}    danos_cli.ipsec_sa_packets    ${R3}    ${user}    ${pa}
    Log    R1 SA packets ${before1} -> ${after1}
    Log    R3 SA packets ${before3} -> ${after3}

    Should Be True    ${after1} > ${before1}    R1 encrypted no traffic
    Should Be True    ${after3} > ${before3}    R3 encrypted no traffic

Validate OSPF status on R1
    Log    Validate OSPF status on R1
    ${output}    ShowService    ${R1}   ${user}    ${pa}    ${validate_ospf_status}
    danos_cli.pr    ${output}
    ${o}    Evaluate    ''.join(${output})
    Should Contain    ${o}    Full

Validate OSPF status on R3
    Log    Validate OSPF status on R3
    ${output}    ShowService    ${R3}   ${user}    ${pa}    ${validate_ospf_status}
    danos_cli.pr    ${output}
    ${o}    Evaluate    ''.join(${output})
    Should Contain    ${o}    Full

Validate VPN tunnel status on R1
    Log    VPN tunnel status on R1
    ${output}    ShowService    ${R1}   ${user}    ${pa}    ${validate_vpn_tunnel_status}
    danos_cli.pr    ${output}
    ${o}    Evaluate    ''.join(${output})
    Should Contain    ${o}    up

Validate VPN tunnel status on R3
    Log    VPN tunnel status on R3
    ${output}    ShowService    ${R3}   ${user}    ${pa}    ${validate_vpn_tunnel_status}
    danos_cli.pr    ${output}
    ${o}    Evaluate    ''.join(${output})
    Should Contain    ${o}    up

Validate VPN IPSEC status on R1
    Log    VPN IPSEC status on R1
    ${output}    ShowService    ${R1}   ${user}    ${pa}    ${validate_vpn_ipsec_status}
    danos_cli.pr    ${output}
    ${o}    Evaluate    ''.join(${output})
    Should Contain    ${o}    Running PID

Validate VPN IPSEC status on R3
    Log    VPN IPSEC status on R3
    ${output}    ShowService    ${R3}   ${user}    ${pa}    ${validate_vpn_ipsec_status}
    danos_cli.pr    ${output}
    ${o}    Evaluate    ''.join(${output})
    Should Contain    ${o}    Running PID
