#!/usr/bin/env python3
"""
SyncTogether Parallels Host Bridge
---------------------------------
Forwards network traffic from the Parallels virtual adapter (10.211.55.1)
to macOS loopback (127.0.0.1) so Windows guest VMs can reach Supabase,
Edge Functions, and Next.js running on the Mac host.

Usage (on macOS Terminal):
    python3 scripts/parallels-bridge.py
    # or via dev.sh:
    ./scripts/dev.sh --parallels
"""

import os
import signal
import socket
import sys
import threading
import time

PORTS = [
    54321,  # Supabase API / Kong
    54322,  # Supabase Postgres
    54323,  # Supabase Studio
    3000,   # Next.js Web Dev Server
]

HOST_IP = os.environ.get("PARALLELS_HOST_IP", "10.211.55.1")

def pipe(source, destination):
    try:
        while True:
            data = source.recv(4096)
            if not data:
                break
            destination.sendall(data)
    except Exception:
        pass
    finally:
        try:
            source.close()
        except Exception:
            pass
        try:
            destination.close()
        except Exception:
            pass

def bridge_port(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind((HOST_IP, port))
    except Exception as e:
        print(f"[-] Could not bind to {HOST_IP}:{port} - {e}", flush=True)
        return

    server.listen(10)
    print(f"[+] Bridging {HOST_IP}:{port} -> 127.0.0.1:{port}", flush=True)

    while True:
        try:
            client_sock, _ = server.accept()
            target_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            target_sock.connect(("127.0.0.1", port))
            t1 = threading.Thread(target=pipe, args=(client_sock, target_sock), daemon=True)
            t2 = threading.Thread(target=pipe, args=(target_sock, client_sock), daemon=True)
            t1.start()
            t2.start()
        except Exception:
            pass

def main():
    signal.signal(signal.SIGTERM, lambda sig, frame: sys.exit(0))
    print("=== SyncTogether Parallels Host Bridge ===", flush=True)
    print(f"Targeting host adapter: {HOST_IP}\n", flush=True)

    threads = []
    for port in PORTS:
        t = threading.Thread(target=bridge_port, args=(port,), daemon=True)
        t.start()
        threads.append(t)

    print("\nBridge is active. Press Ctrl+C to stop.", flush=True)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopping bridge.", flush=True)
        sys.exit(0)

if __name__ == "__main__":
    main()
