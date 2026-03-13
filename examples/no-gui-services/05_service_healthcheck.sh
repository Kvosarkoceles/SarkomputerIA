#!/usr/bin/env bash
set -euo pipefail

check_http() {
  local url="$1"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' -m 5 "$url" || echo 000)"
  printf '%-38s -> HTTP %s\n' "$url" "$code"
}

check_tcp() {
  local host="$1"
  local port="$2"
  python3 - "$host" "$port" <<'PY'
import socket, sys
host=sys.argv[1]
port=int(sys.argv[2])
s=socket.socket(); s.settimeout(2)
try:
    s.connect((host, port))
    print(f"TCP {host}:{port:<5} -> ABIERTO")
except Exception as e:
    print(f"TCP {host}:{port:<5} -> CERRADO ({e})")
finally:
    s.close()
PY
}

echo "=== Chequeos HTTP ==="
check_http "http://localhost:5050/"
check_http "http://localhost:8888/"
check_http "http://localhost:5002/v1/models"
check_http "http://localhost:8188/"

echo
echo "=== Chequeos TCP ==="
check_tcp "127.0.0.1" "11434"
check_tcp "127.0.0.1" "5002"
check_tcp "127.0.0.1" "5003"
check_tcp "127.0.0.1" "8888"
check_tcp "127.0.0.1" "8188"
