#!/usr/bin/env python3
"""
Bans whole /24 subnets that are spraying wildcard-DNS vhost-scan probes
(plesk.page, v6.army/rocks/navy, dns.army, glueops-testing, etc) across
many distinct IPs, each staying under fail2ban's bad-hosts jail per-IP
threshold (2 hits / 10 min) by spreading requests thin across days and
across a whole address range.

fail2ban (jail: bad-hosts, see /etc/fail2ban/jail.d/bad-hosts.conf) already
handles the fast/single-IP case by tailing the same log. This script covers
the pattern fail2ban structurally can't: many IPs, few hits each.

Run daily via ban-scanner-subnets.timer. Idempotent - re-running only acts
on subnets that cross the threshold and aren't already banned.
"""
import ipaddress
import re
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timedelta

LOG_PATH = "/home/www/caddy-logs/bad-hosts.log"
BANNED_IPS_FILE = "/home/www/banned-ips.txt"
LOOKBACK_DAYS = 3
MIN_UNIQUE_IPS = 15  # out of 254 in a /24

# Never ban these, no matter what shows up in the log.
SAFE_EXCLUDE = [
    ipaddress.ip_network("15.204.67.0/24"),  # this server's own public IP lives here
]

LINE_RE = re.compile(
    r'^(?P<ts>\d{4}/\d{2}/\d{2}) \S+.*"remote_ip":\s*"(?P<ip>[0-9.]+)"'
)


def parse_recent_ips():
    cutoff = datetime.now() - timedelta(days=LOOKBACK_DAYS)
    by_subnet = defaultdict(set)
    with open(LOG_PATH, "r", errors="replace") as f:
        for line in f:
            m = LINE_RE.match(line)
            if not m:
                continue
            try:
                ts = datetime.strptime(m.group("ts"), "%Y/%m/%d")
            except ValueError:
                continue
            if ts < cutoff:
                continue
            ip = m.group("ip")
            try:
                addr = ipaddress.ip_address(ip)
            except ValueError:
                continue
            if addr.version != 4:
                continue
            subnet = ipaddress.ip_network(f"{addr}/24", strict=False)
            by_subnet[subnet].add(ip)
    return by_subnet


def is_safe_excluded(subnet):
    return any(subnet == s or subnet.subnet_of(s) for s in SAFE_EXCLUDE)


def already_banned(subnet):
    result = subprocess.run(
        ["iptables", "-C", "DOCKER-USER", "-s", str(subnet), "-j", "DROP"],
        capture_output=True,
    )
    return result.returncode == 0


def ban_subnet(subnet):
    subprocess.run(
        ["iptables", "-I", "DOCKER-USER", "-s", str(subnet), "-j", "DROP"],
        check=True,
    )


def append_to_banned_file(entries):
    marker = "# Noticed but NOT banned"
    with open(BANNED_IPS_FILE, "r") as f:
        content = f.read()
    lines_to_add = "\n".join(entries) + "\n"
    if marker in content:
        content = content.replace(marker, lines_to_add + "\n" + marker, 1)
    else:
        content = content.rstrip("\n") + "\n" + lines_to_add
    with open(BANNED_IPS_FILE, "w") as f:
        f.write(content)


def main():
    by_subnet = parse_recent_ips()
    today = datetime.now().strftime("%Y-%m-%d")

    candidates = []
    for subnet, ips in by_subnet.items():
        if len(ips) < MIN_UNIQUE_IPS:
            continue
        if is_safe_excluded(subnet):
            print(f"skip {subnet}: safe-excluded", file=sys.stderr)
            continue
        if already_banned(subnet):
            continue
        candidates.append((subnet, len(ips)))

    if not candidates:
        print("no new subnets to ban")
        return

    new_entries = []
    for subnet, n in sorted(candidates, key=lambda x: -x[1]):
        ban_subnet(subnet)
        line = (
            f"{str(subnet):<18}{today}   wildcard-DNS vhost scan spread across subnet "
            f"(auto-banned by ban-scanner-subnets.py), {n}/254 IPs hit in last {LOOKBACK_DAYS}d"
        )
        new_entries.append(line)
        print(f"banned {subnet} ({n} unique IPs in last {LOOKBACK_DAYS}d)")

    append_to_banned_file(new_entries)
    subprocess.run(["netfilter-persistent", "save"], check=True)
    print(f"saved {len(new_entries)} new subnet ban(s)")


if __name__ == "__main__":
    main()
