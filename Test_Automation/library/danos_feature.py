#!/usr/bin/python3
# SPDX-License-Identifier: LGPL-2.1-only
"""Helpers for the EVPN and multicast suites.

Those suites check state the Vyatta CLI does not print as a table: the data
plane's own counters and MAC tables (vplsh, JSON) and FRR (vtysh). Both are
reached over ssh from the robot container, so everything here is a thin
wrapper around `sshpass ssh` that returns text or parsed JSON and raises with
the router's answer when a command does not do what the caller asked.

Nothing here decides pass or fail on its own; the suite's assertions do. The
one exception is `cli_commit`, which raises when the commit is rejected,
because a rejected commit otherwise looks like a feature that does not work.
"""
import json
import re
import subprocess

SSH_OPTS = ["-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=10",
            "-o", "LogLevel=ERROR"]

# Lines the commit path prints that are noise on a test image.
_NOISE = re.compile(r"sssd|configuration db|grub|boot-loader|crash dump",
                    re.I)
_COMMIT_FAIL = re.compile(r"commit failed|failed to commit|invalid|"
                          r"is not valid|not a valid|ambiguous|"
                          r"configuration path.*not valid", re.I)


def _ssh(ip, command, stdin=None, timeout=180):
    argv = ["sshpass", "-p", "vyatta", "ssh"] + SSH_OPTS + [
        "vyatta@%s" % ip, command]
    res = subprocess.run(argv, input=stdin, capture_output=True, text=True,
                         timeout=timeout)
    return (res.stdout + res.stderr).strip()


def router_run(ip, command, timeout=180):
    """Run a shell command on the router and return its output."""
    return _ssh(ip, command, timeout=timeout)


def vtysh(ip, *commands):
    """Run one or more vtysh commands (each a separate -c) and return output."""
    args = " ".join("-c '%s'" % c for c in commands)
    return _ssh(ip, "sudo vtysh %s 2>&1" % args)


def vtysh_config(ip, *lines):
    """Enter configure mode and apply lines, returning the output."""
    return vtysh(ip, "configure terminal", *lines)


def cli_commit(ip, *commands):
    """Apply configuration commands in one session and commit.

    Raises if any command or the commit is rejected, with the router's reply.
    """
    body = "".join('vcli -s $SID -c "%s" 2>&1;' % c for c in commands)
    script = ('SID=$$; eval "$(cli-shell-api getSessionEnv $SID)"; '
              'cli-shell-api setupSession; %s '
              'vcli -s $SID -c commit 2>&1; '
              'cli-shell-api teardownSession' % body)
    out = _ssh(ip, script)
    lines = [ln for ln in out.splitlines()
             if ln.strip() and not _NOISE.search(ln)]
    text = "\n".join(lines)
    if _COMMIT_FAIL.search(text):
        raise AssertionError("commit on %s was rejected:\n%s" % (ip, text))
    return text


def clear_config(ip, restore_iface="", restore_address="dhcp"):
    """Remove what earlier suites left, in one transaction.

    `restore_iface` re-adds the management address inside the same session so
    a product image, whose management port is a dataplane port, keeps its way
    in (see mgmt_keywords.robot).
    """
    cmds = ["delete interfaces dataplane", "delete interfaces tunnel",
            "delete interfaces bridge", "delete interfaces loopback",
            "delete protocols", "delete policy", "delete security",
            "delete vpn", "delete resources"]
    if restore_iface:
        cmds.append("set interfaces dataplane %s address %s"
                    % (restore_iface, restore_address))
    # "delete" of a node that does not exist is an error for vcli but not a
    # failed commit; run each delete on its own session-free line and ignore
    # that, then commit once.
    body = "".join('vcli -s $SID -c "%s" >/dev/null 2>&1;' % c
                   for c in cmds)
    script = ('SID=$$; eval "$(cli-shell-api getSessionEnv $SID)"; '
              'cli-shell-api setupSession; %s '
              'vcli -s $SID -c commit 2>&1; '
              'cli-shell-api teardownSession' % body)
    out = _ssh(ip, script)
    # FRR config written straight through vtysh is outside the DANOS tree.
    _ssh(ip, "for a in $(sudo vtysh -c 'show running-config' 2>/dev/null "
             "| awk '/^router bgp/{print $3}'); do "
             "sudo vtysh -c 'configure terminal' -c \"no router bgp $a\" "
             ">/dev/null 2>&1; done")
    return out


def vplsh(ip, command):
    """Run a dataplane command and return the raw output."""
    return _ssh(ip, "sudo /opt/vyatta/bin/vplsh -l -c '%s' 2>/dev/null"
                % command)


def vplsh_json(ip, command):
    """Run a dataplane command and parse its JSON answer."""
    out = vplsh(ip, command)
    # Anything before the first brace is ssh or login noise, not the answer.
    out = out[out.find("{"):] if "{" in out else out
    try:
        return json.loads(out)
    except ValueError:
        raise AssertionError("not JSON from `%s` on %s: %r"
                             % (command, ip, out[:300]))


def send_script(ip, script_text, *args):
    """Run a python3 program on the router, fed over stdin.

    Over stdin and not `python3 -c`: an inline program loses its quoting on
    the way through ssh and vbash and silently does nothing, and zero counters
    are exactly what a broken forwarding path looks like.
    """
    out = _ssh(ip, "python3 - %s" % " ".join(args), stdin=script_text)
    if "sent " not in out:
        raise AssertionError("sender printed no 'sent N' on %s: %r"
                             % (ip, out[:300]))
    return out


SEND_V4 = '''
import socket, sys, time
group, source, count = sys.argv[1], sys.argv[2], int(sys.argv[3])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 16)
s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(source))
for _ in range(count):
    s.sendto(b"S" * 200, (group, 5000))
    time.sleep(0.001)
print("sent", count)
'''

SEND_V6 = '''
import socket, struct, sys, time
group, iface, count = sys.argv[1], sys.argv[2], int(sys.argv[3])
s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_MULTICAST_HOPS, 16)
s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_MULTICAST_IF,
             struct.pack("I", socket.if_nametoindex(iface)))
for _ in range(count):
    s.sendto(b"6" * 200, (group, 5000))
    time.sleep(0.001)
print("sent", count)
'''


def send_multicast_v4(ip, group, source, count):
    return send_script(ip, SEND_V4, group, source, str(count))


def send_multicast_v6(ip, group, iface, count):
    return send_script(ip, SEND_V6, group, iface, str(count))


def mif_counters(ip, family="mif"):
    """Per-interface multicast counters: {iface: (in, out, punt)}.

    `family` is "mif" or "mif6". The JSON key follows the command, and the
    IPv6 command is `multicast mif6`, not `multicast6 mif`.
    """
    data = vplsh_json(ip, "multicast %s" % family)
    return dict((m["interface"],
                 (int(m["pkt_in"]), int(m["pkt_out"]),
                  int(m["pkt_out_punt"])))
                for m in data.get(family, []))


def mif_in(ip, iface, family="mif"):
    return mif_counters(ip, family).get(iface, (0, 0, 0))[0]


def mif_out(ip, iface, family="mif"):
    return mif_counters(ip, family).get(iface, (0, 0, 0))[1]


def fcstat_packets(ip, group, family="fcstat"):
    """Packets counted by the forwarding-cache entry for `group` (0 if none)."""
    data = vplsh_json(ip, "multicast %s" % family)
    total = 0
    for e in data.get(family, []):
        if e.get("group") == group:
            total += int(e.get("packets", 0))
    return total


def evpn_mac_entry(ip, mac):
    """Dataplane VXLAN MAC entry for `mac` as a dict, or None.

    The dump prints the MAC in canonical form; an image that still prints
    "IPAddr" instead of "remote_ip" predates the NTF_EXT_LEARNED work and
    cannot answer the question this is used for, so that is an error and not
    a missing entry.
    """
    data = vplsh_json(ip, "vxlan macs show")
    for table in data.get("mac_table", []):
        for e in table.get("entries", []):
            if "IPAddr" in e:
                raise AssertionError("dataplane predates vxlan_newneigh()")
            if e.get("mac") == mac:
                return e
    return None


def vxlan_out_discards(ip):
    data = vplsh_json(ip, "vxlan stats show")
    return int(data["vxlan_stats"]["OutDiscards"])


def ping_received(ip, target, count=3):
    """Replies received by pinging `target` from the router."""
    out = _ssh(ip, "ping -c %d -W 2 %s 2>&1 | grep -oE '[0-9]+ received'"
               % (count, target))
    m = re.search(r"(\d+) received", out)
    return int(m.group(1)) if m else 0


def interface_mac(ip, iface):
    return _ssh(ip, "cat /sys/class/net/%s/address" % iface).strip()
