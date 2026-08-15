#!/bin/bash
# Install Agent News Bot as a systemd service on Linux. Run as root.
#
# Creates a dedicated service user, installs the Python package under a prefix,
# creates state directories, installs a systemd unit from the shipped example,
# and starts the service. Everything is overridable via environment variables:
#
#   PREFIX      install prefix for the package        (default /opt/agent-news-bot)
#   STATE_DIR   writable state (ledger + token + snapshot) (default /var/lib/agent-news-bot)
#   SVC_USER    dedicated service account             (default agentnewsbot)
#
# Example:  sudo PREFIX=/opt/agent-news-bot ./install.sh
set -euo pipefail

PREFIX="${PREFIX:-/opt/agent-news-bot}"
STATE_DIR="${STATE_DIR:-/var/lib/agent-news-bot}"
SVC_USER="${SVC_USER:-agentnewsbot}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "This installer must run as root (it creates a system user and unit)." >&2
  exit 1
fi

# 1) dedicated, no-login service user
id "$SVC_USER" >/dev/null 2>&1 || useradd --system --create-home \
  --home-dir "$STATE_DIR" --shell /usr/sbin/nologin \
  --comment "Agent News Bot" "$SVC_USER"

# 2) state directories owned by the service user
install -d -o "$SVC_USER" -g "$SVC_USER" -m 0750 \
  "$STATE_DIR" "$STATE_DIR/export" "$STATE_DIR/shared"

# 3) install the package and CLI wrapper
install -d -m 0755 "$PREFIX"
cp -r "$HERE/agent_newsbot" "$PREFIX/"
install -m 0755 "$HERE/agent-newsbot" /usr/local/bin/agent-newsbot

# 4) systemd unit from the shipped example, rewritten to the chosen paths/user
sed -e "s#/opt/agent-news-bot#${PREFIX}#g" \
    -e "s#/var/lib/agent-news-bot#${STATE_DIR}#g" \
    -e "s#^User=agentnewsbot#User=${SVC_USER}#" \
    -e "s#^Group=agentnewsbot#Group=${SVC_USER}#" \
    "$HERE/agent-news-bot.service.example" > /etc/systemd/system/agent-news-bot.service

systemctl daemon-reload
systemctl enable --now agent-news-bot.service
sleep 1
systemctl is-active agent-news-bot.service || true

echo "Installed Agent News Bot."
echo "CLI: agent-newsbot status"
echo "API: http://127.0.0.1:${AGENT_NEWSBOT_PORT:-18765}/health"
echo "Bearer token: ${STATE_DIR}/export/bridge.token"
