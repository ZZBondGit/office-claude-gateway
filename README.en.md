# Office Claude Gateway

<div align="center">

**A lightweight gateway that connects the Claude for Office add-in to Chinese LLM APIs**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Python 3.10+](https://img.shields.io/badge/Python-3.10%2B-blue.svg)](https://www.python.org/downloads/)
[![Tests](https://img.shields.io/badge/tests-109%20passed-brightgreen.svg)](gateway_unified/tests)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)](#3-installation-recommended-install-wizard)

**🌐 [中文](README.md) | English**

</div>

---

An **Anthropic Messages API gateway** for **Microsoft Office add-ins** (Excel / Word / PowerPoint / Outlook) and any Claude-compatible client.

> Connect the Claude for Office add-in to DeepSeek / Kimi (Moonshot) / MiMo (Xiaomi) / MiniMax — no Anthropic account required.

**Key features**:
- 🏢 **Office-native compatibility** — Exposes the Anthropic Messages API surface (`/v1/messages`, `/v1/models`), works out of the box with the Claude for Office add-in
- 🔀 **Multiple providers** — One-click choice of DeepSeek / Kimi / MiMo / MiniMax, with automatic model-name mapping
- 🎭 **Model alias mapping** — The add-in sends `claude-sonnet-5` etc.; the gateway maps it to the provider's real model (e.g. DeepSeek's `deepseek-v4-flash`)
- 🌐 **Web Search auto-execution** — Built-in DuckDuckGo search that auto-fills `tool_result`
- ♻️ **Upstream retry** — Automatic retry with exponential backoff on 5xx / 429 / network errors
- 📊 **Token usage stats** — Input/output/cache token counts logged per request
- 🔒 **HTTPS direct** — uvicorn native TLS, no reverse proxy needed, cross-platform

**Use cases**:
- 💼 Users in China who want the Claude add-in in Excel/Word without an Anthropic account
- 🏢 Enterprises that want to unify Office AI capabilities with existing model API quotas
- 🧪 Developers who want to point the Claude add-in at any Anthropic-compatible model service

**Live screenshot** (Claude sidebar in Word, model routed through the gateway):

![Claude add-in in Word](docs/word-claude-addin.jpg)

---

## Table of Contents

1. [How It Works](#1-how-it-works)
2. [Supported Providers & Model Mapping](#2-supported-providers--model-mapping)
3. [Installation (Recommended: Install Wizard)](#3-installation-recommended-install-wizard)
4. [Manual Installation](#4-manual-installation)
5. [Add-in Configuration](#5-add-in-configuration)
6. [Client Certificate Installation](#6-client-certificate-installation)
7. [Auto-start (systemd / launchd / Task Scheduler)](#7-auto-start-systemd--launchd--task-scheduler)
8. [Configuration Reference](#8-configuration-reference)
9. [Web Search Capability](#9-web-search-capability)
10. [API Endpoints](#10-api-endpoints)
11. [Testing](#11-testing)

---

## 1. How It Works

### The problem it solves

Microsoft's **Claude for Office** add-in (shared across Excel / Word / PowerPoint / Outlook) can only connect to the Anthropic API by default. But an Anthropic account:
- Is not accessible/registerable from mainland China
- Requires a foreign credit card
- Is billed in USD, which can be expensive

This gateway acts as a **protocol converter + router** in between:

```
┌──────────────┐     Anthropic Messages API      ┌──────────────────┐
│  Excel/Word  │ ──POST /v1/messages───────────► │  Office Claude   │
│  PPT/Outlook │     model: claude-sonnet-5       │     Gateway      │
│  (Claude add-in) ◄──SSE stream response─────── │  (HTTPS 8443)    │
└──────────────┘                                  └────────┬─────────┘
                                                           │ provider choice
                                                           ▼
                              ┌──────────┬──────────┬──────────┬──────────┐
                              │ DeepSeek │  Kimi    │   MiMo   │ MiniMax  │
                              └──────────┴──────────┴──────────┴──────────┘
                                  (all support Anthropic /v1/messages)
```

### Workflow

1. **Add-in sends request** — standard Anthropic-format request to the gateway
2. **Sanitize** — filter content blocks the upstream doesn't support, cap request body size
3. **Model mapping** — map `claude-opus-4-7` / `claude-sonnet-5` etc. to the selected provider's real models
4. **Route & forward** — forward to the upstream chosen at install time
5. **Stream passthrough** — the upstream SSE stream is "fixed up" and passed through
6. **Usage stats** — extract token usage from responses into logs

### Why all providers work

DeepSeek / Kimi / MiMo / MiniMax all **officially support the Anthropic `/v1/messages` API** (each exposes an `/anthropic` path), so the gateway only needs to rewrite the model name and forward.

---

## 2. Supported Providers & Model Mapping

### Providers

| Provider | Requires | Notes |
|---|---|---|
| **DeepSeek** | `DEEPSEEK_API_KEY` | Recommended default, cheap & stable |
| **Kimi** (Moonshot) | `KIMI_API_KEY` | Coding Plan / PAYG, image support |
| **MiMo** (Xiaomi) | `MIMO_API_KEY` | PAYG / Token Plan, multi-region |
| **MiniMax** | `MINIMAX_API_KEY` | PAYG / Coding Plan, image support |

### Model mapping

The add-in sees Claude model names; the gateway maps them to each provider's real models:

| Add-in sends | DeepSeek | Kimi | MiMo | MiniMax |
|---|---|---|---|---|
| `claude-opus-4-7` / `opus` | `deepseek-v4-pro` | `kimi-k2.6` | `mimo-v2.5-pro` | `MiniMax-M2.7` |
| `claude-sonnet-5` / `sonnet` | `deepseek-v4-flash` | `kimi-k2.5` | `mimo-v2.5` | `MiniMax-M2.5` |

Overridable via env: `MODEL_PRIMARY` / `MODEL_MID` / `MODEL_FAST`.

### Model version notes

The add-in (2026 build) requires specific model versions:
- **Outlook** requires Claude Opus 4.7+ and Sonnet 5+
- The gateway therefore advertises **`claude-opus-4-7`** and **`claude-sonnet-5`** in `/v1/models`
- Old `claude-opus-4-5` / `claude-sonnet-4-5` cause the add-in to repeatedly poll models but never enter a conversation
- **Haiku is intentionally not exposed** to avoid an unnecessary third tier in the add-in

---

## 3. Installation (Recommended: Install Wizard)

The project ships **interactive install wizards for three platforms**:

| Platform | Command |
|---|---|
| **Linux** | `bash install-linux.sh` |
| **macOS** | `bash install-mac.sh` |
| **Windows** (Git Bash) | `bash install-windows.sh` |

The wizard guides you through:

1. **Choose provider** — DeepSeek / Kimi / MiMo / MiniMax
2. **Enter API key** — paste your provider key
3. **Enable LAN?** — `y` binds `0.0.0.0` and **auto-detects the local LAN IP** (lists candidates on multi-NIC, no manual lookup); `n` binds localhost only (`https://127.0.0.1:8443`)
4. **Generate HTTPS cert** — auto-installs mkcert, generates cert + CA, and **prints full certificate paths** (for copying to other devices)
5. **Write config** — updates `.env` (ACTIVE_PROVIDER + API key)
6. **Install deps** — creates venv and installs
7. **Auto-start?** — `y` installs the auto-start service (Linux systemd / macOS launchd / Windows Task Scheduler); `n` skips and prints the manual start command
8. **Verify** — checks the gateway is ready

After install it prints:

```
Add-in settings:
  Gateway URL: https://192.168.10.5:8443
  API Token:   sk-xxx*** (your key)

Client certificate (for other devices):
  ~/office-gateway-certs/mkcert-rootCA.crt
  Install to "Trusted Root Certification Authorities" then restart Office

Certificate files:
  ~/office-gateway-certs/
```

> **Why must you choose a provider at install time?** Because the Office add-in does not support custom Base URLs, and provider key prefixes (e.g. `sk-`) are not reliably distinguishable. Choosing at install time fixes `ACTIVE_PROVIDER`, which is the most robust approach.

---

## 4. Manual Installation

Prefer not to use the wizard? Manual steps work on Linux / macOS / Windows.

### 4.1 Requirements

- **Python 3.10+**
- **mkcert** (https://github.com/FiloSottile/mkcert/releases)

### 4.2 Install dependencies

```bash
cd gateway_unified
python -m venv .venv
.venv/bin/pip install -e .
```

### 4.3 Generate certificate

```bash
mkdir -p ~/office-gateway-certs && cd ~/office-gateway-certs
mkcert -install
mkcert 192.168.10.5 localhost 127.0.0.1    # replace with your LAN IP
cp ~/.local/share/mkcert/rootCA.pem mkcert-rootCA.crt
```

### 4.4 Configure .env

```bash
cd gateway_unified
cp .env.example .env
# edit .env: set ACTIVE_PROVIDER and the corresponding API key
```

### 4.5 Start (HTTPS direct)

```bash
cd gateway_unified && source .venv/bin/activate
python -m uvicorn --app-dir src claude_gateway.main:app \
  --host 0.0.0.0 --port 8443 \
  --ssl-keyfile ~/office-gateway-certs/192.168.10.5+2-key.pem \
  --ssl-certfile ~/office-gateway-certs/192.168.10.5+2.pem
```

- `--host 0.0.0.0`: **enable LAN** — other devices reach it at `https://<IP>:8443`
- `--host 127.0.0.1`: **local only** — `https://127.0.0.1:8443`

> **Why no nginx?** You don't need it. uvicorn natively supports `--ssl-keyfile/--ssl-certfile` for HTTPS. Simpler, cross-platform, one less component. CORS is handled by the gateway itself.

Verify:

```bash
curl -sk https://127.0.0.1:8443/healthz
# → {"status":"ok","provider":"deepseek"}
```

---

## 5. Add-in Configuration

In the Claude for Office add-in settings (Cloud provider or gateway → Gateway):

| Field | Value |
|---|---|
| **Gateway URL** | `https://192.168.10.5:8443` (**no /v1** — the add-in appends it) |
| **API Token** | Your provider API key (the one entered during install) |

The add-in will call:
- `GET /v1/models` (model discovery on login)
- `POST /v1/messages` (conversation)

> ⚠️ **The add-in only supports HTTPS** — its taskpane loads from `https://pivot.claude.ai`, and the browser blocks mixed content. An `http://` URL fails with "Failed to fetch".

---

## 6. Client Certificate Installation

The gateway's HTTPS cert is signed by a local mkcert CA, so **client devices must trust that CA**:

### 6.1 Windows

1. Copy `mkcert-rootCA.crt` (in `~/office-gateway-certs/` on the gateway machine) to Windows
2. **Double-click → Install Certificate** → store location **Local Machine** (admin required)
3. "Place all certificates in the following store" → Browse → **Trusted Root Certification Authorities** → Finish
4. **Fully quit and restart Excel** (so the WebView reloads the cert store)

Verify (PowerShell):

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object {$_.Subject -like "*mkcert*"}
```

### 6.2 macOS

1. Double-click `mkcert-rootCA.crt`
2. Keychain Access → certificate → "Always Trust"

### 6.3 Certificate troubleshooting

```powershell
Test-NetConnection 192.168.10.5 -Port 8443      # False = network/firewall issue
curl.exe -v https://192.168.10.5:8443/healthz   # inspect cert errors
```

| Error | Meaning | Fix |
|---|---|---|
| `SEC_E_UNTRUSTED_ROOT` (0x80090325) | CA not in root store | Reinstall per 6.1 into "Trusted Root Certification Authorities" |
| `CRYPT_E_NO_REVOCATION_CHECK` (0x80092012) | Revocation check failed | **Normal** — internal certs have no CRL; ignore |
| Returns `{"status":"ok"...}` | Cert OK | Add-in layer issue: restart Excel |

> ⚠️ If the add-in reports "Could not reach gateway" but the logs are all `OPTIONS` requests, check for **duplicate CORS headers** — don't put another CORS-header-adding reverse proxy (e.g. nginx `add_header`) in front of the gateway. CORS is handled uniformly by the gateway; duplicate headers are silently rejected by the add-in's WebView.

---

## 7. Auto-start (systemd / launchd / Task Scheduler)

The install wizard creates and enables the auto-start service (Linux systemd / macOS launchd / Windows Task Scheduler); choosing "no" skips it. Manual setup per platform:

### 7.1 Linux (systemd)

`~/.config/systemd/user/office-claude-gateway.service`:

```ini
[Unit]
Description=Office Claude Gateway (Python/FastAPI, HTTPS)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
WorkingDirectory=/home/zzbond/projects/office-claude-gateway/gateway_unified
ExecStart=/home/zzbond/projects/office-claude-gateway/gateway_unified/.venv/bin/python -m uvicorn --app-dir src claude_gateway.main:app --host 0.0.0.0 --port 8443 --ssl-keyfile /home/zzbond/office-gateway-certs/192.168.10.5+2-key.pem --ssl-certfile /home/zzbond/office-gateway-certs/192.168.10.5+2.pem
Restart=on-failure
RestartSec=3
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
```

Enable & start:

```bash
systemctl --user daemon-reload
systemctl --user enable --now office-claude-gateway.service

# Common commands
systemctl --user status office-claude-gateway.service   # status
systemctl --user restart office-claude-gateway.service  # restart
journalctl --user -u office-claude-gateway.service -f   # logs
```

> Note: `ExecStart` uses `python -m uvicorn` rather than the `uvicorn` executable (the project venv has uvicorn in site-packages but no bin entry point).

### 7.2 macOS (launchd)

The wizard generates `~/Library/LaunchAgents/com.officeclaude.gateway.plist`. Key entries: `RunAtLoad=true` (start at login), `KeepAlive=true` (restart on crash), `StandardOutPath/StandardErrorPath` for logs.

```bash
launchctl load ~/Library/LaunchAgents/com.officeclaude.gateway.plist
# Unload: launchctl unload ...
```

### 7.3 Windows (Task Scheduler)

The wizard generates `~/office-claude-gateway-start.bat` and registers it with `schtasks /Create /SC ONSTART` (admin required).

Manual: Win+R → `shell:startup`, drop the .bat there for auto-start at login.

---

## 8. Configuration Reference

| Variable | Default | Description |
|---|---|---|
| `ACTIVE_PROVIDER` | `deepseek` | Provider: deepseek / kimi / mimo / minimax |
| `GATEWAY_PORT` | `8443` | Listen port |
| `MAX_REQUEST_BODY_BYTES` | `4MB` | Request body cap |
| `DEFAULT_MAX_TOKENS` | `4096` | Default max_tokens |
| `ALIAS_OPUS_VERSIONED` | `claude-opus-4-7` | Opus advertised model name |
| `ALIAS_SONNET_VERSIONED` | `claude-sonnet-5` | Sonnet advertised model name |
| `MODEL_PRIMARY/MID/FAST` | provider-specific | Three-tier real model names |
| `LOG_CONTENT_REDACT` | `true` | Log redaction |
| `ALLOWED_ORIGIN` | `https://pivot.claude.ai` | CORS allowed origin (don't change) |
| `UPSTREAM_RETRY_ATTEMPTS` | `3` | Upstream retry count |
| `UPSTREAM_RETRY_BASE_DELAY` | `0.5` | Retry base backoff (seconds) |

Common config (DeepSeek):

```env
ACTIVE_PROVIDER=deepseek
DEEPSEEK_API_KEY=sk-xxx
ALIAS_OPUS_VERSIONED=claude-opus-4-7
ALIAS_SONNET_VERSIONED=claude-sonnet-5
```

---

## 9. Web Search Capability

```env
ENABLE_WEB_SEARCH_TOOL=false          # enable the web_search tool
ENABLE_AUTO_WEB_SEARCH_EXECUTION=true # gateway auto-executes search
AUTO_WEB_SEARCH_MAX_RESULTS=5         # results per search
AUTO_WEB_SEARCH_TIMEOUT_SECONDS=20    # search timeout
AUTO_WEB_SEARCH_MAX_ROUNDS=2          # max auto-search rounds
```

**Mode A: passthrough only** — `ENABLE_WEB_SEARCH_TOOL=true` + `ENABLE_AUTO_WEB_SEARCH_EXECUTION=false`: pass through the web_search structure; whether it works depends on the upstream.

**Mode B: gateway auto-executes (recommended)** — the gateway normalizes web_search into a client tool, runs local DuckDuckGo search, fills in `tool_result`, converges over multiple rounds, with XML tool_call fallback.

---

## 10. API Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/healthz` | Health check |
| `GET` | `/v1/models` (also `/models`) | Model list |
| `POST` | `/v1/messages` | Chat/generation (SSE streaming supported) |

---

## 11. Testing

```bash
cd gateway_unified
pip install -e ".[dev]"
pytest tests/ -v          # 109 tests
```

Covers: provider routing, model mapping, input sanitization, SSE chunking, retry, token usage, web search loop.

---

## License

MIT
