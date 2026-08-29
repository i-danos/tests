#!/usr/bin/python3
# * Copyright (c) 2020-2021, Happiest Minds Technologies Limited Intellectual Property. All rights reserved.
# *
# * SPDX-License-Identifier: LGPL-2.1-only
import time
import vymgmt
from pexpect import pxssh


class Router(vymgmt.Router):
    """vymgmt.Router with the two adjustments a DANOS router needs.

    vymgmt targets VyOS, and two of its assumptions do not hold here:

    * It builds its pxssh session with stock options, so ssh insists on
      verifying the host key. A test router boots from a live image and
      generates a fresh key every time, so that check can only fail -- the
      session dies before a single command is sent, and vymgmt reports the
      unhelpful "Could not establish connection to host".

    * DANOS pipes operational-mode output through a pager. pexpect drives a
      terminal the pager considers dumb, so it stops at "Press RETURN to
      continue" and never hands the shell prompt back. pxssh's prompt() then
      times out and vymgmt raises "Connection timed out" -- for a command
      that in fact ran perfectly.

    Both are fixed at login: the ssh options go in when the session is
    built, and the pager is turned off for the rest of the session.
    """

    SSH_OPTIONS = {
        "StrictHostKeyChecking": "no",
        "UserKnownHostsFile": "/dev/null",
    }

    def login(self):
        conn = pxssh.pxssh(options=self.SSH_OPTIONS)
        conn.login(self._Router__address, self._Router__user,
                   password=self._Router__password,
                   port=self._Router__port)
        # vymgmt keeps this state private; a subclass that replaces login()
        # has to populate it so the inherited methods keep working.
        self._Router__conn = conn
        self._Router__logged_in = True
        self.run_op_mode_command("export VYATTA_PAGER=cat")

def config_set(ip, user, ps, cmd):
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    handle.configure()
    handle.set(cmd)
    handle.commit()
    handle.save()
    handle.exit()
    handle.logout()

def ipsec_sa_packets(ip, user, ps):
    """Total packets carried by the dataplane's IPsec SAs.

    tcpdump cannot answer "is this traffic encrypted" on DANOS. The interfaces
    belong to the DPDK dataplane -- /sys/class/net/<if>/device does not exist
    for them -- so what the kernel sees, and what tcpdump therefore captures,
    is the cleartext copy handed up to it. Encryption happens in userspace and
    the ciphertext goes straight out of the physical port. Captures on all
    three routers show plaintext ICMP and no ESP even while the tunnel is
    carrying traffic correctly.

    The SA counters do answer it: they only advance when packets are actually
    encrypted or decrypted.
    """
    cmd = ("/opt/vyatta/bin/vplsh -l -c 'ipsec sad' | "
           "python3 -c \"import sys,json;"
           "d=json.load(sys.stdin);"
           "print(sum(s.get('packets',0) for s in d.get('sas',[])))\"")
    handle = vymgmt.Router(ip, user, password=ps, port=22)
    handle.login()
    out = handle.run_op_mode_command('sudo ' + cmd)
    handle.exit()
    handle.logout()
    for line in reversed(out.split("\n")):
        line = line.strip()
        if line.isdigit():
            return int(line)
    return 0

def config_show_service(ip, user, ps, cmd):
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    handle.configure()
    out = handle.run_conf_mode_command(cmd)
    handle.exit()
    handle.logout()
    output = out.split("\n")
    output2 = ''.join([str(elem) for elem in output])
    return output2

def config_delete(ip, user, ps, cmd):
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    handle.configure()
    handle.delete(cmd)
    handle.commit()
    handle.save()
    handle.exit()
    handle.logout()

def show_command(ip, user, ps, cmd):
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    out = handle.run_op_mode_command(cmd)
    handle.exit()
    handle.logout()
    output = out.split("\n")
    #output2 = ''.join([str(elem) for elem in output])
    return output

def config_ipsecvpn(ip, user, ps, cmd):
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    handle.configure()
    for line in cmd:
        print(line)
        handle.set(line)
    handle.commit()
    handle.save()
    handle.exit()
    handle.logout()

def config_mplsldp(ip, user, ps, cmd):
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    handle.configure()
    for line in cmd:
        print(line)
        handle.set(line)
    handle.commit()
    handle.save()
    handle.exit()
    handle.logout()

def config(ip, user, ps, cmd):
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    handle.configure()
    for line in cmd:
        print(line)
        handle.set(line)
    handle.commit()
    handle.save()
    handle.exit()
    handle.logout()

def apply_rule(ip, user, ps, iface, rule, cmd):
    command = cmd.replace('INTERFACE',iface).replace('RULE',rule)
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    handle.configure()
    handle.set(command)
    handle.commit()
    handle.save()
    handle.exit()
    handle.logout()

def delete_rule(ip, user, ps, iface, rule, cmd):
    command = cmd.replace('INTERFACE',iface).replace('RULE',rule)
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    handle.configure()
    handle.delete(command)
    handle.commit()
    handle.save()
    handle.exit()
    handle.logout()

def config_show_ipsecvpn(ip, user, ps, cmd):
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    handle.configure()
    out = handle.run_conf_mode_command(cmd)
    handle.exit()
    handle.logout()
    output = out.split("\n")
    return output

def config_show_mplsldp(ip, user, ps, cmd):
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    handle.configure()
    out = handle.run_conf_mode_command(cmd)
    handle.exit()
    handle.logout()
    output = out.split("\n")
    return output

def config_show(ip, user, ps, cmd):
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    handle.configure()
    out = handle.run_conf_mode_command(cmd)
    handle.exit()
    handle.logout()
    output = out.split("\n")
    return output

def sendping(ip, user, ps, vpnip):
    c1='sudo killall -9 ping'
    cmd='sudo ping -c30 ' + vpnip + ' > /dev/null 2>&1 &'
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    handle.run_op_mode_command(c1)
    out = handle.run_op_mode_command(cmd)
    handle.exit()
    handle.logout()

def capture_traffic(ip, user, ps, iface):
    cmd='sudo timeout 5 tcpdump -i ' + iface
    handle = Router(ip, user, password=ps, port=22)
    handle.login()
    out = handle.run_op_mode_command(cmd)
    handle.exit()
    handle.logout()
    output = out.split("\n")
    return output

def pr(st):
    for line in st:
        print(line)
