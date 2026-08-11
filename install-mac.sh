#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/install-common.sh"

show_banner
detect_python
ask_provider
ask_api_key
ask_lan
setup_cert
write_env
install_deps
ask_autostart

LABEL="com.officeclaude.gateway"
PLIST_FILE="$HOME/Library/LaunchAgents/${LABEL}.plist"

if [ "$AUTOSTART" = "yes" ]; then
  echo ""
  info "创建 launchd 自启任务..."
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${GATEWAY_DIR}/.venv/bin/python</string>
        <string>-m</string>
        <string>uvicorn</string>
        <string>--app-dir</string>
        <string>src</string>
        <string>claude_gateway.main:app</string>
        <string>--host</string>
        <string>${HOST_BIND}</string>
        <string>--port</string>
        <string>${GATEWAY_PORT}</string>
        <string>--ssl-keyfile</string>
        <string>${CERTS_DIR}/${LAN_IP}+2-key.pem</string>
        <string>--ssl-certfile</string>
        <string>${CERTS_DIR}/${LAN_IP}+2.pem</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${GATEWAY_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME}/.office-claude-gateway.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.office-claude-gateway.err.log</string>
</dict>
</plist>
EOF
  launchctl unload "$PLIST_FILE" 2>/dev/null || true
  launchctl load "$PLIST_FILE"
  sleep 2
  if curl -sk -m 3 "https://127.0.0.1:${GATEWAY_PORT}/healthz" >/dev/null 2>&1; then
    ok "已注册开机自启并启动"
  else
    warn "服务启动可能失败，查看日志: cat ~/.office-claude-gateway.err.log"
  fi
else
  echo ""
  info "未选择开机自启，跳过 launchd 安装。"
fi

if [ "$AUTOSTART" != "yes" ]; then
  echo ""
  echo "  手动启动命令："
  echo "    cd $GATEWAY_DIR && source .venv/bin/activate"
  echo "    python -m uvicorn --app-dir src claude_gateway.main:app --host ${HOST_BIND} --port ${GATEWAY_PORT} --ssl-keyfile $CERTS_DIR/${LAN_IP}+2-key.pem --ssl-certfile $CERTS_DIR/${LAN_IP}+2.pem"
  echo ""
fi

show_complete
verify_gateway
