# Gateway Unified (Python 实现)

这是 **Office Claude Gateway** 的 Python 实现目录
（FastAPI + uvicorn）。

> 📖 完整文档（原理 / 部署 / 配置 / 排障 / 证书安装）请见仓库根目录的
> [README.md](../README.md)。

## 快速命令

```bash
# 安装
pip install -e .

# 配置
cp .env.example .env   # 填 ACTIVE_PROVIDER + 对应 API key

# 本机调试（HTTP，仅 curl 用）
uvicorn --app-dir src claude_gateway.main:app --host 127.0.0.1 --port 8790

# 局域网部署：配合 nginx HTTPS 反代（详见根 README 第 4 节）
uvicorn --app-dir src claude_gateway.main:app --host 0.0.0.0 --port 8790
```

> ⚠️ **Office 插件只支持 HTTPS**——本机 HTTP 仅用于 curl 调试，
> 插件接入必须走 nginx + mkcert 证书的 HTTPS（见根 README）。

## 测试

```bash
pip install -e ".[dev]"
pytest tests/ -v
```

当前 109 个测试全通过。

## 目录

- `src/claude_gateway/main.py` — FastAPI 入口、路由、自动工具回路
- `src/claude_gateway/providers.py` — Provider 路由与模型映射
- `src/claude_gateway/sanitize.py` — 请求清洗
- `src/claude_gateway/stream.py` — SSE 修正与工具分片聚合
- `src/claude_gateway/retry.py` — 上游重试
- `src/claude_gateway/usage.py` — token 用量统计
- `src/claude_gateway/models.py` — /v1/models 构建
- `src/claude_gateway/web_search.py` — DuckDuckGo 搜索
- `src/claude_gateway/log_mw.py` / `logging_setup.py` — 日志与脱敏
