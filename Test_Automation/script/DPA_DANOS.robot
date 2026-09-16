*** Settings ***
Metadata        Version           1.0

Documentation   The forwarding-abstraction operational views, from the CLI.
...
...             What this covers and why it did not exist before: the data
...             plane records, per forwarding object, which backend programmed
...             it and in what state -- full, partial, no-resource, no-support,
...             not-needed, error. Since the FAL grew a capability model and the
...             ability to load more than one backend, it also records what each
...             backend can do and which one was selected for each capability.
...
...             None of that was reachable from the CLI. "show platform" was not
...             a valid command on any 2608 image: the YANG package was
...             commented out of the ISO when vendor hardware was dropped,
...             sharing the word "platform" with IPMI, SFP and the opennsl
...             plugin. Everything under it could be read only through vplsh,
...             which is not a CLI and cannot be driven from here -- so every
...             capability added to that layer sat outside the regression suite.
...
...             Topology: none. These are read-only operational commands about
...             the box itself, so a single router answers for all of them and
...             any topology will do.
...
...             Testplan Goals:-
...             1. The commands exist at all
...             2. Backends: the software data plane answers for every capability
...             3. Objects: every class is listed, with a reason where it cannot
...                be walked
...             4. Objects carry the backend that holds them
...             5. Filtering by state across the box agrees with filtering one class
...             6. The per-class subset views are reachable

Library           SSHLibrary
Library           String
Library           Collections
Resource          ../keyword/DPA_DANOS_keywords.robot

*** Variables ***
${R1}      192.168.203.155

*** Test Cases ***
The platform dataplane commands are present
    [Documentation]    Fails if the op-mode YANG package is absent from the
    ...                image, which is the state every 2608 image was in until
    ...                the package list was corrected.
    The command show platform dataplane is available on ${R1}
    The command show platform dataplane backends is available on ${R1}
    The command show platform dataplane objects is available on ${R1}

Backends view reports no offload backend and says what that means
    Backends view reports the software data plane on ${R1}

Every capability is selected to the software data plane
    Every capability is answered by sw-dataplane on ${R1}

Object view lists every class, with a reason for the ones it cannot walk
    Object view lists its classes on ${R1}

Programmed objects name the backend holding them
    Programmed state carries a backend on ${R1}

Filtering by state across the box agrees with filtering one class
    Objects in one state span at least what one class has on ${R1}

Per-class programming state is reachable for every subset
    Per-object state is reachable per class on ${R1}
