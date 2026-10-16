#!/usr/bin/env python3
"""Live UDP flow regression: python3 tests/check-bridge.py MAC_IP.

Run from Linux. Sends no mouse/keyboard input and leaves streaming untouched.
Each heartbeat uses a fresh client socket, exactly like mac-screens-wake.
"""
import socket
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: python3 tests/check-bridge.py MAC_IP')
host = socket.gethostbyname(sys.argv[1])
for number in range(1100):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(5)
        sock.sendto(b'K', (host, 45991))
        reply, peer = sock.recvfrom(64)
        assert peer == (host, 45991) and reply == b'READY', (number, peer, reply)
    if (number + 1) % 100 == 0:
        print(f'{number + 1} fresh UDP sessions answered', flush=True)
print('PASS: bridge still accepts new clients beyond the old flow-table limit')
