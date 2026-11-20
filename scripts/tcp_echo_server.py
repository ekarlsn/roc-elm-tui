#!/usr/bin/env python3
"""Minimal single-connection TCP echo server used by process tests.

Listens on 127.0.0.1:8085, accepts one client, and echoes everything it
receives straight back until the client disconnects. This keeps the TCP
tests self-contained (no dependency on `ncat`/`nc`).
"""
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 8085))
    server.listen(1)
    while True:
        conn, _ = server.accept()
        with conn:
            while True:
                data = conn.recv(1024)
                if not data:
                    break
                conn.sendall(data)
