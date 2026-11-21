# Cursor Local Mode

让 Cursor 的 Agent 走本机 / 自建的 OpenAI 兼容网关（magpie、LiteLLM、Ollama、vLLM……），
而不是 Cursor 云端。做法是把 `Cursor.app` **复制一份**，打开 workbench bundle 里被写死的
`localMode` 开关，重新 ad-hoc 签名后独立启动。原始安装完全不动。

## 为什么需要改二进制

标准版 Cursor 的 Agent 推理请求由 Cursor 云端发出，所以设置里填
`http://127.0.0.1:...` 永远不会通。客户端自带一条本地 Agent 代码路径，但被
`localMode:!1` 关掉了。翻成 `!0` 后，Agent 直接从本机进程调用配置的 OpenAI 兼容地址。

## 快速开始

```bash
# 1. 网关就绪（需要支持 /v1/chat/completions、流式、tool calling）
curl -fsS http://127.0.0.1:3425/v1/models

# 2. 生成补丁副本（约 1.4G，APFS 克隆很快）
./scripts/make-local-app.sh /Applications/Cursor.app "$HOME/Applications/CursorLocal.app"

# 3. 启动（先改脚本顶部的 GATEWAY_BASE_URL / GATEWAY_API_KEY）
./scripts/launch-cursor-local.command
```

启动脚本会校验补丁、探活网关，再用 `launchctl setenv` 注入
`CURSOR_LOCAL_AGENT_BASE_URL` / `CURSOR_LOCAL_AGENT_API_KEY` 并
`open -na ... --disable-updates --user-data-dir=...`。

验证：

```bash
grep -r 'baseUrlSource\|gateway_http_status\|gateway_model_id' \
  "$HOME/Library/Application Support/CursorLocal/logs" | tail -20
```

看到 `gateway_http_status=200` 和正确的 `gateway_model_id` 即打通。

## 作为 Codex skill 使用

把整个目录放进 `${CODEX_HOME:-$HOME/.codex}/skills/`，然后

```
Use $cursor-local-mode to point my Cursor Agent at http://127.0.0.1:3425/v1
```

细节见 [SKILL.md](SKILL.md)，故障排查见
[references/troubleshooting.md](references/troubleshooting.md)。

## 边界与风险

- **只影响 Agent 推理**。Tab 补全、代码索引、embeddings、遥测仍然走 Cursor 云端。
- **不是账号隔离**。副本与主安装共用 bundle id、`~/.cursor` 和机器/设备 ID，两边活动
  可以被关联。不要用它规避平台检测。
- 修改并重签已签名应用不受官方支持，可能违反 Cursor 服务条款。
- 每次更新 Cursor 都会覆盖补丁，必须带 `--disable-updates` 启动，升级后重新生成副本。
- 补丁位置随版本变化：用 `grep -abo 'localMode:!1' <bundle>` 定位，不要写死偏移。

## 官方本地版（可选）

Cursor 另外发布了 `cursor-local` 渠道的构建，面向本地/离线 Agent，无需打补丁：

```
https://api2.cursor.sh/updates/download/golden/darwin-arm64-user/cursor-local/latest
https://api2.cursor.sh/updates/download/golden/darwin-x64-user/cursor-local/latest
```

## License

MIT
