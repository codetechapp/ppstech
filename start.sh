#!/bin/bash
# PPS Tech - Xray (VLESS over WebSocket + XHTTP) derriere Caddy.
# Variables optionnelles : UUID, PORT, WS_PATH, XH_PATH.
set -u

UUID="${UUID:-50505354-4543-48a1-a7f3-9c2e5d81b04f}"
PORT="${PORT:-8080}"
WS_PATH="${WS_PATH:-/@ppstech}"
XH_PATH="${XH_PATH:-/@ppstech/xh}"
CONF="${CONF_DIR:-/etc}"

if ! [[ "$UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "UUID invalide : $UUID" >&2
  exit 1
fi

mkdir -p "$CONF/xray" "$CONF/caddy"

cat > "$CONF/xray/config.json" <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "ws-in",
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$UUID" } ], "decryption": "none" },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH" }
      }
    },
    {
      "tag": "xhttp-in",
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$UUID" } ], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": { "path": "$XH_PATH", "mode": "auto" }
      }
    }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "outboundTag": "block",
        "ip": [
          "127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
          "169.254.0.0/16", "100.64.0.0/10", "::1/128", "fc00::/7", "fe80::/10"
        ]
      }
    ]
  }
}
JSON

cat > "$CONF/caddy/Caddyfile" <<CADDY
{
  admin off
  auto_https off
}

:$PORT {
  respond /health "ok" 200
  reverse_proxy $WS_PATH 127.0.0.1:10001
  reverse_proxy $XH_PATH* 127.0.0.1:10002 {
    flush_interval -1
  }
}
CADDY

[ "${GEN_ONLY:-0}" = "1" ] && exit 0

export XDG_DATA_HOME=/tmp XDG_CONFIG_HOME=/tmp

xray run -c "$CONF/xray/config.json" &
XRAY_PID=$!
caddy run --config "$CONF/caddy/Caddyfile" --adapter caddyfile &
CADDY_PID=$!

trap 'kill $XRAY_PID $CADDY_PID 2>/dev/null; exit 0' TERM INT

# Si l'un des deux s'arrete, on quitte en erreur : Cloud Run relance le conteneur.
wait -n $XRAY_PID $CADDY_PID
echo "Un processus s'est arrete, redemarrage du conteneur." >&2
kill $XRAY_PID $CADDY_PID 2>/dev/null
exit 1
