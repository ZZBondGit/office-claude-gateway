#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ️  ${NC}$*"; }
ok()    { echo -e "${GREEN}✅ ${NC}$*"; }
warn()  { echo -e "${YELLOW}⚠️  ${NC}$*"; }
err()   { echo -e "${RED}❌ ${NC}$*"; }

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_DIR="$PROJECT_ROOT/gateway_unified"
CERTS_DIR="$HOME/office-gateway-certs"
GATEWAY_PORT="8443"

show_banner() {
  echo ""
  echo "============================================================"
  echo "  🚀  Office Claude Gateway 安装向导"
  echo "      让 Excel/Word/PPT 的 Claude 插件接入国产大模型 API"
  echo "============================================================"
  echo ""
}

detect_python() {
  info "检测环境..."
  PYTHON_BIN=""
  for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1; then
      ver=$("$cand" -c 'import sys; print(sys.version_info.major, sys.version_info.minor)' 2>/dev/null || echo "0 0")
      major=$(echo $ver | cut -d' ' -f1); minor=$(echo $ver | cut -d' ' -f2)
      if [ "$major" -ge 3 ] && [ "$minor" -ge 10 ]; then PYTHON_BIN="$cand"; break; fi
    fi
  done
  if [ -z "$PYTHON_BIN" ]; then
    err "需要 Python 3.10+，请先安装：https://www.python.org/downloads/"
    exit 1
  fi
  ok "Python: $("$PYTHON_BIN" --version 2>&1)"
}

ask_provider() {
  echo ""
  echo "🏭 选择一个厂商（插件将使用该厂商的 API）："
  echo "  1) DeepSeek（推荐，便宜稳定）"
  echo "  2) Kimi (Moonshot)"
  echo "  3) MiMo (小米)"
  echo "  4) MiniMax"
  read -rp "🔢 输入编号 [1-4，默认 1]: " PROVIDER_CHOICE
  case "${PROVIDER_CHOICE:-1}" in
    1) PROVIDER="deepseek"; PROMPT_KEY="DEEPSEEK_API_KEY" ;;
    2) PROVIDER="kimi";    PROMPT_KEY="KIMI_API_KEY" ;;
    3) PROVIDER="mimo";    PROMPT_KEY="MIMO_API_KEY" ;;
    4) PROVIDER="minimax"; PROMPT_KEY="MINIMAX_API_KEY" ;;
    *) PROVIDER="deepseek"; PROMPT_KEY="DEEPSEEK_API_KEY"; warn "无效输入，默认 DeepSeek" ;;
  esac
  ok "厂商: $PROVIDER"
}

ask_api_key() {
  echo ""
  read -rp "🔑 输入你的 ${PROMPT_KEY}（粘贴 API key）: " API_KEY
  if [ -z "$API_KEY" ]; then
    err "API key 不能为空"
    exit 1
  fi
  ok "API key 已记录（长度 ${#API_KEY}）"
}

ask_lan() {
  echo ""
  echo "🌐 是否开启局域网访问？"
  echo "  [y] 是 — 其他设备（如 Windows Excel）通过 https://<IP>:${GATEWAY_PORT} 访问"
  echo "  [n] 否 — 仅本机访问 https://127.0.0.1:${GATEWAY_PORT}"
  read -rp "🔘 是否开启局域网? [y/N 默认否]: " LAN_CHOICE
  case "${LAN_CHOICE:-n}" in
    y|Y|yes|YES) LAN_ENABLED="yes" ;;
    *) LAN_ENABLED="no"; warn "未开启局域网，仅本机可用" ;;
  esac

  if [ "$LAN_ENABLED" = "yes" ]; then
    IP_LIST=""
    if command -v hostname >/dev/null 2>&1 && hostname -I 2>/dev/null | grep -q .; then
      IP_LIST="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$')"
    fi
    if [ -z "$IP_LIST" ]; then
      IP_LIST="$(ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' || true)"
    fi
    if [ -z "$IP_LIST" ]; then
      IP_LIST="$(ifconfig 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' || true)"
    fi

    LAN_IP=""
    IP_COUNT="$(echo "$IP_LIST" | grep -c . || true)"
    if [ -z "$IP_LIST" ]; then
      err "无法自动检测局域网 IP，请手动输入"
      read -rp "🔢 输入网关机器的局域网 IP: " LAN_IP
    elif [ "$IP_COUNT" -eq 1 ]; then
      LAN_IP="$(echo "$IP_LIST" | head -1)"
      ok "自动检测到局域网 IP: $LAN_IP"
    else
      echo "检测到多个网络接口，请选择："
      echo "$IP_LIST" | nl -w2 -s') '
      read -rp "🔢 输入编号 [默认 1]: " IP_CHOICE
      IP_CHOICE="${IP_CHOICE:-1}"
      LAN_IP="$(echo "$IP_LIST" | sed -n "${IP_CHOICE}p")"
      if [ -z "$LAN_IP" ]; then
        warn "无效选择，取第一个"
        LAN_IP="$(echo "$IP_LIST" | head -1)"
      fi
      ok "局域网 IP: $LAN_IP"
    fi

    HOST_BIND="0.0.0.0"
    ok "插件将访问 https://${LAN_IP}:${GATEWAY_PORT}"
  else
    LAN_IP="127.0.0.1"
    HOST_BIND="127.0.0.1"
    ok "仅本机访问 https://127.0.0.1:${GATEWAY_PORT}"
  fi
}

setup_cert() {
  echo ""
  info "准备 HTTPS 证书（mkcert）..."
  if ! command -v mkcert >/dev/null 2>&1; then
    warn "未安装 mkcert，尝试自动安装..."
    OS="$(uname -s)"
    ARCH="$(uname -m)"
    case "$ARCH" in x86_64|amd64) ARCH="amd64";; aarch64|arm64) ARCH="arm64";; *) warn "未知架构: $ARCH，请手动安装 mkcert";; esac
    MKCERT_URL="https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-${OS,,}-${ARCH}"
    if command -v curl >/dev/null 2>&1; then
      curl -sL "$MKCERT_URL" -o /tmp/mkcert && chmod +x /tmp/mkcert
      mkdir -p "$HOME/.local/bin" && mv /tmp/mkcert "$HOME/.local/bin/mkcert"
      export PATH="$HOME/.local/bin:$PATH"
      ok "mkcert 已安装到 ~/.local/bin"
    else
      err "请手动安装 mkcert：$MKCERT_URL"
      exit 1
    fi
  fi

  mkdir -p "$CERTS_DIR"
  cd "$CERTS_DIR"
  mkcert -install >/dev/null 2>&1 || warn "mkcert -install 警告（不影响生成）"
  if [ ! -f "${LAN_IP}+2.pem" ]; then
    mkcert "$LAN_IP" localhost 127.0.0.1
  fi
  cp "$HOME/.local/share/mkcert/rootCA.pem" "$CERTS_DIR/mkcert-rootCA.crt" 2>/dev/null || true
  ok "HTTPS 证书已生成:"
  ok "  📜 证书: $CERTS_DIR/${LAN_IP}+2.pem"
  ok "  🔑 私钥: $CERTS_DIR/${LAN_IP}+2-key.pem"
  ok "  🏷️  CA（给其他设备装）: $CERTS_DIR/mkcert-rootCA.crt"
  echo ""
  info "把上面的 mkcert-rootCA.crt 复制到客户端设备（Windows/macOS）安装信任："
  info "  🪟 Windows: 双击 → 安装证书 → 本地计算机 → 受信任的根证书颁发机构"
  info "  🍎 macOS:   双击 → 钥匙串 → 始终信任"
  echo ""
}

write_env() {
  echo ""
  info "写入配置 .env ..."
  if [ ! -f "$GATEWAY_DIR/.env" ]; then
    cp "$GATEWAY_DIR/.env.example" "$GATEWAY_DIR/.env"
  fi
  sed -i.bak "s|^ACTIVE_PROVIDER=.*|ACTIVE_PROVIDER=${PROVIDER}|" "$GATEWAY_DIR/.env" 2>/dev/null || true
  sed -i.bak "s|^${PROMPT_KEY}=.*|${PROMPT_KEY}=${API_KEY}|" "$GATEWAY_DIR/.env" 2>/dev/null || true
  if ! grep -q "^ACTIVE_PROVIDER=" "$GATEWAY_DIR/.env"; then echo "ACTIVE_PROVIDER=${PROVIDER}" >> "$GATEWAY_DIR/.env"; fi
  if ! grep -q "^${PROMPT_KEY}=" "$GATEWAY_DIR/.env"; then echo "${PROMPT_KEY}=${API_KEY}" >> "$GATEWAY_DIR/.env"; fi
  rm -f "$GATEWAY_DIR/.env.bak"
  ok ".env 已更新（ACTIVE_PROVIDER=${PROVIDER}）"
}

install_deps() {
  echo ""
  info "安装 Python 依赖（首次较慢）..."
  cd "$GATEWAY_DIR"
  if [ ! -d ".venv" ]; then
    "$PYTHON_BIN" -m venv .venv
  fi
  .venv/bin/pip install -q -e . 2>/dev/null || .venv/bin/pip install -q fastapi "uvicorn[standard]" httpx python-dotenv 2>&1 | tail -2
  .venv/bin/pip install -q "uvicorn[standard]" 2>/dev/null || true
  ok "依赖已安装"
}

ask_autostart() {
  echo ""
  echo "🔄 是否设置开机自启？"
  echo "  [y] 是 — 开机自动启动网关（推荐，Linux 用 systemd）"
  echo "  [n] 否 — 不安装自启，需要时手动启动"
  read -rp "🔘 是否开机自启? [y/N 默认否]: " AUTOSTART_CHOICE
  case "${AUTOSTART_CHOICE:-n}" in
    y|Y|yes|YES) AUTOSTART="yes" ;;
    *) AUTOSTART="no"; warn "不设置开机自启" ;;
  esac
}

show_complete() {
  echo ""
  echo "============================================================"
  echo "  🎉  安装完成！"
  echo "============================================================"
  echo ""
  echo "  📱 插件里填写："
  echo "    Gateway URL: https://${LAN_IP}:${GATEWAY_PORT}"
  echo "    API Token:   ${API_KEY:0:6}***（你的 key）"
  echo ""
  echo "  🏷️  客户端证书（其他设备安装用）："
  echo "    $CERTS_DIR/mkcert-rootCA.crt"
  echo "    装到「受信任的根证书颁发机构」后重启 Office"
  echo ""
  echo "  📁 证书文件位置："
  echo "    $CERTS_DIR/"
  echo ""
}

verify_gateway() {
  echo "  验证网关..."
  KEY_FOR_TEST="$API_KEY"
  curl -sk -m 5 "https://127.0.0.1:${GATEWAY_PORT}/healthz" >/dev/null 2>&1 \
    && ok "网关已就绪: https://${LAN_IP}:${GATEWAY_PORT}/healthz" \
    || warn "网关未就绪，检查服务/日志"
}
