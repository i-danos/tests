*** Settings ***
Documentation     Keep the management path alive across a suite's clear step.
...
...               Every suite opens by deleting configuration -- "delete
...               interfaces dataplane", or in IPSEC_VPN and MPLS_LDP the wider
...               "delete interfaces". On the test image that is harmless: its
...               overlay adds exclude-interfaces=ens31,ens30 to
...               dataplane.conf, so management sits on a kernel-side NIC that
...               configd does not own and the delete cannot reach it.
...
...               The product image has no such overlay. Every NIC is claimed by
...               the dataplane, so management has to live on a dp0sN port --
...               and the clear step then deletes the suite's own way back in.
...               Nothing reports this as a configuration error: the commit
...               succeeds and the connection simply stops.
...
...               The fix is not to narrow the delete, which would let residue
...               from an earlier suite survive. It is to put the management
...               address back inside the same configuration session. configd is
...               transactional and commits the net difference, so the port's
...               final state is unchanged and it never goes down. Verified on
...               the product image over SSH: a test address on dp0s4 was
...               removed, dp0s3 kept 10.0.2.15/24, and the session stayed up
...               throughout.
...
...               Off by default, so the test image behaves exactly as before.
...               Enable it per run:
...
...                   robot --variable MGMT_restore:dp0s3 ...
...
...               ${MGMT_address} defaults to dhcp; set it to a prefix such as
...               10.0.2.15/24 for a statically addressed management port.

*** Variables ***
${MGMT_restore}       ${EMPTY}
${MGMT_address}       dhcp

*** Keywords ***
Restore management address
    [Documentation]    Re-add the management address inside the caller's open
    ...                configuration session, before its commit. A no-op unless
    ...                ${MGMT_restore} names an interface.
    IF    '${MGMT_restore}' != ''
        Write    set interfaces dataplane ${MGMT_restore} address ${MGMT_address}
        Read Until    \#
    END
