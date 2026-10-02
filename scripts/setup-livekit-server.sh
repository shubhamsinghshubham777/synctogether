#!/usr/bin/env bash
# Sets up a production LiveKit server for SyncTogether on a fresh Ubuntu VPS
# (x86_64 or ARM, e.g. Oracle Cloud's Always Free Ampere A1).
#
# Run ON THE SERVER, from a checkout of this repo:
#   sudo ./scripts/setup-livekit-server.sh av.example.com
#
# Before running: point a DNS A record for the domain at this server's public
# IP, and open the ports below in your cloud provider's firewall (on Oracle:
# the VCN security list). This script opens them in the host firewall too.
#
# Safe to re-run: existing keys are kept, so connected apps keep working.
set -euo pipefail

DOMAIN="${1:-}"
if [[ -z "$DOMAIN" ]]; then
  echo "usage: sudo $0 <domain>   e.g. sudo $0 av.example.com" >&2
  exit 64
fi
if [[ $EUID -ne 0 ]]; then
  echo "run with sudo" >&2
  exit 1
fi

DIR="$(cd "$(dirname "$0")/../deploy/livekit" && pwd)"

echo "==> Installing Docker"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

echo "==> Opening host firewall ports"
# Oracle's Ubuntu images ship an iptables REJECT rule that blocks everything
# but SSH, even once the VCN security list allows it - the most common reason
# a "correctly configured" Oracle server is unreachable. Rules go in before
# that REJECT, and are persisted across reboots.
open_port() {
  local proto=$1 port=$2
  iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null ||
    iptables -I INPUT 5 -p "$proto" --dport "$port" -j ACCEPT
}
open_port tcp 80     # Caddy: certificate challenge
open_port tcp 443    # Caddy: wss signalling
open_port tcp 7881   # WebRTC over TCP
open_port udp 7882   # WebRTC media
open_port udp 3478   # TURN
open_port udp 30000:40000   # TURN relay range (LiveKit's default)
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 7881/tcp && ufw allow 7882/udp && ufw allow 3478/udp && ufw allow 30000:40000/udp
fi
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >/dev/null
netfilter-persistent save >/dev/null

echo "==> Writing config"
if [[ -f "$DIR/livekit.yaml" ]]; then
  KEY=$(awk '/^keys:/{getline; sub(/^ */,""); split($0,a,": "); print a[1]}' "$DIR/livekit.yaml")
  SECRET=$(awk '/^keys:/{getline; sub(/^ */,""); split($0,a,": "); print a[2]}' "$DIR/livekit.yaml")
  echo "    keeping existing API key $KEY"
else
  KEY="API$(openssl rand -hex 6)"
  SECRET="$(openssl rand -base64 36 | tr -d '/+=' | cut -c1-43)"
fi
sed -e "s|__API_KEY__|$KEY|" -e "s|__API_SECRET__|$SECRET|" \
  "$DIR/livekit.yaml.template" > "$DIR/livekit.yaml"
sed -e "s|__DOMAIN__|$DOMAIN|" "$DIR/Caddyfile.template" > "$DIR/Caddyfile"
chmod 600 "$DIR/livekit.yaml"

echo "==> Starting LiveKit + Caddy"
docker compose -f "$DIR/docker-compose.yml" up -d --pull always

echo "==> Waiting for https://$DOMAIN"
for _ in $(seq 1 30); do
  if curl -fsS "https://$DOMAIN" >/dev/null 2>&1; then break; fi
  sleep 4
done
if curl -fsS "https://$DOMAIN" >/dev/null 2>&1; then
  echo "    LiveKit is answering over TLS"
else
  echo "    Not answering yet. Check DNS, the cloud firewall, and:" >&2
  echo "    docker compose -f $DIR/docker-compose.yml logs" >&2
fi

cat <<OUT

Done. Add this endpoint to supabase/functions/.env (first = preferred), then
  supabase secrets set --env-file supabase/functions/.env

  {"id":"self","url":"wss://$DOMAIN","key":"$KEY","secret":"$SECRET"}

Keep the secret somewhere safe; it is also in $DIR/livekit.yaml.
OUT
