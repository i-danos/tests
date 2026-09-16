*** Settings ***
Documentation     Keywords for the forwarding-abstraction operational views.
...
...               Every assertion here has to hold on a box with no offload
...               backend, because that is every DANOS 2608 box: no FAL plugin
...               loads on this image. "backends loaded: 0" is the correct
...               answer on such a system, not a failure, and the software data
...               plane answers for every capability.
...
...               That constrains what can be checked and is the reason the
...               checks are shaped the way they are. What cannot be exercised
...               here -- the rendering of a loaded backend, and dispatch
...               between two of them -- is covered in the data plane's own
...               whole_dp suite, dp_test_fal_capability.c, against two test
...               plugins.

Library           SSHLibrary
Library           String
Library           Collections

*** Variables ***
${user}    vyatta
${pa}      vyatta

*** Keywords ***
Open an operational session to ${vm}
    ${id}    Open Connection   ${vm}    prompt=$    alias=${vm}    timeout=15
    Login   ${user}    ${pa}
    Execute Command   touch .hushlogin
    RETURN    ${id}

Run operational command ${cmd} on ${vm}
    [Documentation]    Run one op-mode command and return everything it printed.
    ...
    ...                Execute Command rather than Write/Read Until: these
    ...                commands print a table whose last line has no fixed
    ...                shape, and reading until a prompt truncates output at
    ...                whatever happens to arrive first.
    Open an operational session to ${vm}
    ${o}    Execute Command    /opt/vyatta/bin/vyatta-op-cmd-wrapper ${cmd}
    Log    ${o}
    Close All Connections
    RETURN    ${o}

The command ${cmd} is available on ${vm}
    [Documentation]    A command the CLI does not have reports "Invalid
    ...                command" and exits 0, so absence has to be asserted on
    ...                the text. This is the check that fails if the YANG
    ...                package is missing from the image -- which is what it
    ...                was for three releases, the package having been
    ...                commented out of the ISO with the vendor hardware.
    ${o}    Run operational command ${cmd} on ${vm}
    Should Not Contain    ${o}    Invalid command
    RETURN    ${o}

Backends view reports the software data plane on ${vm}
    ${o}    The command show platform dataplane backends is available on ${vm}
    # No FAL plugin loads on this image, so this is the expected reading.
    Should Contain    ${o}    backends loaded: 0
    # The sentence matters as much as the number: without it an operator reads
    # "0" as a fault on a working box.
    Should Contain    ${o}    software data plane
    Should Contain    ${o}    selected for
    RETURN    ${o}

Every capability is answered by ${backend} on ${vm}
    ${o}    Backends view reports the software data plane on ${vm}
    FOR  ${cap}  IN    ipv4    ipv6    vrf    vlan    qinq    mpls
    ...                vxlan    evpn    acl    qos    multicast    hw-offload
        Should Match Regexp    ${o}    (?m)^\\s+${cap}\\s+${backend}\\s*$
    END

Object view lists its classes on ${vm}
    ${o}    The command show platform dataplane objects is available on ${vm}
    FOR  ${cls}  IN    route    route6    mroute    mroute6    mpls-route    vrf
        Should Match Regexp    ${o}    (?m)^\\s+${cls}\\s+yes\\s*$
    END
    # A class that cannot be walked says why. Without the reason an empty class
    # reads as "nothing is programmed here", which is a different statement.
    Should Match Regexp    ${o}    (?m)^\\s+qos-if\\s+no \\(.+\\)\\s*$
    Should Match Regexp    ${o}    (?m)^\\s+qos-vlan\\s+no \\(.+\\)\\s*$
    RETURN    ${o}

Count objects reported by ${cmd} on ${vm}
    ${o}    Run operational command ${cmd} on ${vm}
    ${m}    Get Regexp Matches    ${o}    (?m)^\\s+objects:\\s+(\\d+)\\s*$    1
    Should Not Be Empty    ${m}    ${cmd} printed no object count
    ${n}    Convert To Integer    ${m}[0]
    RETURN    ${n}

Objects in one state span at least what one class has on ${vm}
    [Documentation]    The regression guard for the object filters.
    ...
    ...                The class arrives as a positional argument and its
    ...                position moves: under "objects route no-support" the
    ...                class is $5, under "objects no-support" there is no
    ...                class and $5 is the state. One YANG grouping used for
    ...                both passes --class=no-support in the second case, which
    ...                matches nothing and reports zero objects -- a plausible
    ...                answer, and wrong.
    ...
    ...                So compare the two rather than checking either alone.
    ...                Whatever one class has in a state, the whole box has at
    ...                least that much.
    ${all}      Count objects reported by show platform dataplane objects no-support on ${vm}
    ${route}    Count objects reported by show platform dataplane objects route no-support on ${vm}
    Should Be True    ${route} > 0
    ...    no route objects are in no_support, so this comparison proves nothing
    Should Be True    ${all} >= ${route}
    ...    the whole-box filter (${all}) returned fewer than one class (${route})

Programmed state carries a backend on ${vm}
    [Documentation]    Every object names what holds it. With no plugin loaded
    ...                that is the software data plane for all of them, which
    ...                is still an answer about a working system.
    ${o}    Run operational command show platform dataplane objects on ${vm}
    Should Match Regexp    ${o}    (?m)^\\s+CLASS\\s+STATE\\s+BACKEND\\s+CREATED-BY\\s+KEY\\s*$
    # [^\\S\\n] rather than \\s: \\s matches a newline, and (?m) does not stop it
    # -- (?m) only changes what ^ and $ mean. The first version walked off the
    # end of "route  yes" in the class list above and read "route6" from the
    # line below as if it were this row's backend column. It failed on the
    # first real run, which is the only reason it is not still there.
    ${rows}    Get Regexp Matches    ${o}    (?m)^[^\\S\\n]+route[^\\S\\n]+\\S+[^\\S\\n]+(\\S+)[^\\S\\n]+    1
    Should Not Be Empty    ${rows}    no route object rows were listed
    FOR  ${b}  IN  @{rows}
        Should Be Equal    ${b}    sw-dataplane
    END

Per-object state is reachable per class on ${vm}
    [Documentation]    The five subset views that predate this work. They were
    ...                in the tree, built and packaged, and in no image: the
    ...                YANG package was commented out of the ISO as a hardware
    ...                platform command. Nothing covered them, so nothing said
    ...                so.
    FOR  ${state}  IN    full    partial    no-resource    no-support    not-needed    error
        ${o}    The command show platform dataplane route ${state} is available on ${vm}
    END
