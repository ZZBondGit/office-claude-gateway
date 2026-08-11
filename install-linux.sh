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
ask_autostart

SERVICE_NAME="office-claude-gateway"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"

if [ "$AUTOSTART" = "yes" ]; then
  echo ""
  info "创建 systemd 用户服务..."
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Office Claude Gateway (Python/FastAPI, HTTPS)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
WorkingDirectory=$GATEWAY_DIR
ExecStart=$GATEWAY_DIR/.venv/bin/python -m uvicorn --app-dir src claude_gateway.main:app --host ${HOST_BIND} --port ${GATEWAY_PORT} --ssl-keyfile $CERTS_DIR/${LAN_IP}+2-key.pem --ssl-certfile $CERTS_DIR/${LAN_IP}+2.pem
Restart=on-failure
RestartSec=3
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "${SERVICE_NAME}.service" 2>&1 | tail -1
  sleep 2
  if systemctl --user is-active --quiet "${SERVICE_NAME}.service"; then
    ok "服务已启动并设为开机自启"
  else
    warn "服务启动失败，查看日志: journalctl --user -u ${SERVICE_NAME} -e"
  fi
else
  echo ""
  info "未选择开机自启，跳过 systemd 服务安装。"
fi

if [ "$AUTOSTART" != "yes" ]; then
  echo ""
  echo "  手动启动命令："
  echo "    cd $GATEWAY_DIR && source .venv/bin/activate"
  echo "    python -m uvicorn --app-dir src claude_gateway.main:app --host ${HOST_BIND} --port ${GATEWAY_PORT} --ssl-keyfile $CERTS_DIR/${LAN_IP}+2-key.pem --ssl-certfile $CERTS_DIR/${LAN_IP}+2.pem"
  echo ""
fi

if [ "$AUTOSTART" = "yes" ] && ! systemctl --user is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
  echo ""
  echo "  服务未运行，可手动启动："
  echo "    cd $GATEWAY_DIR && source .venv/bin/activate"
  echo "    python -m uvicorn --app-dir src claude_gateway.main:app --host ${HOST_BIND} --port ${GATEWAY_PORT} --ssl-keyfile $CERTS_DIR/${LAN_IP}+2-key.pem --ssl-certfile $CERTS_DIR/${LAN_IP}+2.pem"
  echo ""
fi

show_complete
verify_gateway
