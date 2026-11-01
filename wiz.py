#!/usr/bin/env python3
"""Control WiZ lights on your local network. No extra packages needed.

Usage:
  python wiz.py find                 # list lights on the network
  python wiz.py on                   # turn on
  python wiz.py off                  # turn off
  python wiz.py dim 40               # brightness 10-100
  python wiz.py temp 3000            # color temperature 2200-6500 K
  python wiz.py set 60 4000          # brightness + temperature together
  python wiz.py status               # current state

Set LIGHT_IPS below after running `find`. Leave it empty to target every light found.
"""
import json
import socket
import sys

LIGHT_IPS = []  # e.g. ["192.168.1.42"]
PORT = 38899


def send(ip, method, params=None, timeout=1.5):
    msg = {"method": method, "params": params or {}}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.settimeout(timeout)
        s.sendto(json.dumps(msg).encode(), (ip, PORT))
        try:
            data, _ = s.recvfrom(1024)
            return json.loads(data)
        except socket.timeout:
            return None


def find(timeout=2.0):
    msg = json.dumps({"method": "getPilot", "params": {}}).encode()
    found = {}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        s.settimeout(timeout)
        s.sendto(msg, ("255.255.255.255", PORT))
        try:
            while True:
                data, addr = s.recvfrom(1024)
                found[addr[0]] = json.loads(data).get("result", {})
        except socket.timeout:
            pass
    return found


def targets():
    if LIGHT_IPS:
        return LIGHT_IPS
    ips = list(find())
    if not ips:
        sys.exit("No lights found. Check that the computer is on the same Wi-Fi.")
    return ips


def pilot(params):
    for ip in targets():
        r = send(ip, "setPilot", params)
        print(f"{ip}: {'ok' if r else 'no response'}")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd, args = sys.argv[1], sys.argv[2:]

    if cmd == "find":
        lights = find()
        if not lights:
            print("No lights found.")
        for ip, state in lights.items():
            print(ip, state)
    elif cmd == "on":
        pilot({"state": True})
    elif cmd == "off":
        pilot({"state": False})
    elif cmd == "dim":
        pilot({"state": True, "dimming": max(10, min(100, int(args[0])))})
    elif cmd == "temp":
        pilot({"state": True, "temp": max(2200, min(6500, int(args[0])))})
    elif cmd == "set":
        pilot({"state": True,
               "dimming": max(10, min(100, int(args[0]))),
               "temp": max(2200, min(6500, int(args[1])))})
    elif cmd == "status":
        for ip in targets():
            print(ip, send(ip, "getPilot"))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
