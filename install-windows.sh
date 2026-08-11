#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/install-common.sh"

# Windows 上 venv 的可执行文件在 Scripts/ 而非 bin/
VENV_BIN="$GATEWAY_DIR/.venv/Scripts"
if [ ! -d "$VENV_BIN" ]; then
  VENV_BIN="$GATEWAY_DIR/.venv/bin"
fi

show_banner
detect_python
ask_provider
ask_api_key
ask_lan
setup_cert
write_env
install_deps
ask_autostart

if [ "$AUTOSTART" = "yes" ]; then
  echo ""
  info "创建 Windows 计划任务（开机自启）..."
  TASK_NAME="OfficeClaudeGateway"
  BAT_FILE="$HOME/office-claude-gateway-start.bat"
  cat > "$BAT_FILE" <<EOF
@echo off
cd /d "$GATEWAY_DIR"
"$VENV_BIN/python.exe" -m uvicorn --app-dir src claude_gateway.main:app --host ${HOST_BIND} --port ${GATEWAY_PORT} --ssl-keyfile "$CERTS_DIR\\${LAN_IP}+2-key.pem" --ssl-certfile "$CERTS_DIR\\${LAN_IP}+2.pem"
EOF
  if command -v schtasks >/dev/null 2>&1; then
    schtasks //Create //TN "$TASK_NAME" //TR "$BAT_FILE" //SC ONSTART //RL HIGHEST //F 2>&1 | tail -1 || warn "计划任务创建失败，请以管理员身份运行 Git Bash"
    ok "已创建开机自启任务: $TASK_NAME"
    ok "启动脚本: $BAT_FILE"
  else
    warn "schtasks 不可用（需 Windows 环境），跳过自启安装"
    warn "手动开机自启：把 $BAT_FILE 放到启动文件夹 (Win+R → shell:startup)"
  fi
else
  echo ""
  info "未选择开机自启，跳过计划任务安装。"
fi

if [ "$AUTOSTART" != "yes" ]; then
  echo ""
  echo "  手动启动命令（Git Bash）："
  echo "    cd $GATEWAY_DIR && source .venv/Scripts/activate"
  echo "    python -m uvicorn --app-dir src claude_gateway.main:app --host ${HOST_BIND} --port ${GATEWAY_PORT} --ssl-keyfile '$CERTS_DIR/${LAN_IP}+2-key.pem' --ssl-certfile '$CERTS_DIR/${LAN_IP}+2.pem'"
  echo ""
fi

show_complete
verify_gateway
