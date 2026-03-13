#!/usr/bin/env python3
import socket

HOST = "127.0.0.1"
PORT = 5003

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(3)

try:
    sock.connect((HOST, PORT))
    print(f"OK: Piper Wyoming TCP es accesible en {HOST}:{PORT}")
    print("Nota: este servicio no es un endpoint web HTTP.")
except Exception as exc:
    print(f"ERROR: no se pudo conectar a Piper Wyoming en {HOST}:{PORT} -> {exc}")
finally:
    sock.close()
