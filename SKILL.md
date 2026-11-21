---
name: cursor-local-mode
description: Make Cursor's Agent use a local OpenAI-compatible gateway (magpie, LiteLLM, Ollama, vLLM) by patching a copy of Cursor.app to enable its built-in local mode. Use when a user wants Cursor Agent on a self-hosted or localhost-only model endpoint.
metadata:
  short-description: Point Cursor Agent at a local gateway
---

# Cursor Local Mode

Cursor's Agent sends inference requests from Cursor's cloud by default, so `127.0.0.1`
or a LAN-only base URL is unreachable no matter what is typed into settings. The
desktop bundle ships a local-agent code path gated by a compile-time flag
(`localMode:!1`) in the workbench bundle. Flipping it in a **copy** of `Cursor.app`
makes the Agent call the configured OpenAI-compatible endpoint from the local process.

Scope: Agent/composer inference only. Tab completion, codebase indexing, embeddings,
and telemetry keep going to Cursor's servers.

## Agree on the limits first

State these before modifying anything, and do not proceed if the user's goal is to
escape account-level detection:

- Modifying and re-signing a signed application is unsupported and may violate
  Cursor's terms of service.
- The copy keeps the same bundle identifier, `~/.cursor`, and machine/device IDs as
  the main install. Accounts and telemetry are **not** isolated; activity from both
  installations can be correlated. Never suggest this hides usage from the vendor.
- Every Cursor update overwrites the patch, so the launcher must pass
  `--disable-updates`.
- Never patch `/Applications/Cursor.app` in place. Always build a separate copy so the
  paid/working install stays usable.

Ask the user for the gateway base URL, the API key value, and the model IDs. Do not
read or print their real key; pass it through an environment variable.

## 1. Verify the gateway

The gateway must speak the OpenAI API and support streaming plus tool calling —
Cursor's Agent refuses to work without tools.

```bash
BASE=http://127.0.0.1:3425/v1   # user's gateway
curl -fsS -m 3 "$BASE/models"
curl -fsS -m 60 "$BASE/chat/completions" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $KEY" \
  -d '{"model":"<model-id>","stream":true,"messages":[{"role":"user","content":"hi"}]}'
```

Build the model list from `/models`; Cursor populates its picker from there (cached
under `cursor/localProviderModelCatalog` in storage).

## 2. Build the patched copy

```bash
scripts/make-local-app.sh /Applications/Cursor.app "$HOME/Applications/CursorLocal.app"
```

The script copies the app (`ditto`, fast on APFS), patches exactly one
`localMode:!1` → `localMode:!0`, ad-hoc re-signs with `codesign --force --deep --sign -`,
and verifies the signature. The byte offset of the flag differs between versions —
locate it with `grep -abo 'localMode:!1' <bundle>` instead of reusing an offset.

## 3. Launch

```bash
scripts/launch-cursor-local.command
```

Edit `APP`, `DATA`, `GATEWAY_BASE_URL` and `GATEWAY_API_KEY` at the top of the script,
or override them as environment variables. Mechanism:

```bash
launchctl setenv CURSOR_LOCAL_AGENT_BASE_URL "$GATEWAY"
launchctl setenv CURSOR_LOCAL_AGENT_API_KEY "$KEY"
open -na "$APP" --args --disable-updates \
  --user-data-dir="$DATA" --extensions-dir="$DATA/extensions"
```

`launchctl setenv` is what reaches the app; exporting variables in the shell does not.
The script unsets them again a few seconds after launch.

## 4. Confirm it resolved locally

```bash
grep -r 'baseUrlSource\|gateway_http_status\|gateway_model_id' \
  "$HOME/Library/Application Support/CursorLocal/logs" | tail -20
```

Healthy output looks like `path=agent result=resolved
baseUrlSource=storage.openAIBaseUrl`, `gateway_http_status=200`, and the expected
`gateway_model_id`, with no `gateway_error_count` growth. Send one Agent message and
confirm the gateway receives the request.

If nothing resolves locally, read [references/troubleshooting.md](references/troubleshooting.md).

## Alternative: official local build

Cursor publishes a separate `cursor-local` channel build that is designed for
local/offline agent work and needs no patch. Prefer it when it is available for the
user's platform and version:

```
https://api2.cursor.sh/updates/download/golden/darwin-arm64-user/cursor-local/latest
https://api2.cursor.sh/updates/download/golden/darwin-x64-user/cursor-local/latest
```

Both redirect to a signed DMG. If that build still has no field for a custom base URL,
fall back to the patch above.
