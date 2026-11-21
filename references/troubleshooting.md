# Troubleshooting

## Where the client logs

`~/Library/Application Support/CursorLocal/logs/<timestamp>/main.log` plus the
`window*/` subdirectories. Search with:

```bash
grep -r 'baseUrlSource\|gateway_http_status\|gateway_model_id\|gateway_error' \
  "$HOME/Library/Application Support/CursorLocal/logs" | tail -30
```

## How the base URL and key are chosen

Base URL, first match wins:

1. `modelDetails.openaiApiBaseUrl` (per-model override in storage)
2. `storage.openAIBaseUrl` (what the settings UI writes)
3. `env:CURSOR_LOCAL_AGENT_BASE_URL`
4. `env:ANTHROPIC_BASE_URL`

API key, first match wins:

1. `modelDetails.apiKeyCredentials.apiKey`
2. `storage.openAIKey`
3. `env:CURSOR_LOCAL_AGENT_API_KEY`
4. `env:ANTHROPIC_AUTH_TOKEN`

A stale UI value silently wins over the environment, so clear the OpenAI Base URL /
API key fields in the copy's settings when debugging env-var launches. The copy stores
its own `storage.openAIKey`; delete that entry if it should not persist.

## Settings UI caveat

"Use OpenAI API Key" + "Override OpenAI Base URL" only take effect in local mode. The
**Verify** button performs a fetch from the local client, so a green check proves the
gateway is reachable from this machine — not that Cursor's cloud could use it. In
unpatched builds the request still goes to the cloud and fails.

## Patch problems

- `expected exactly one 'localMode:!1', found 0`: already patched, or the bundle does
  not contain that literal. Run `grep -abo 'localMode' <bundle>` and inspect the
  surrounding bytes; the flag is minified and may change shape between versions.
- App quits immediately after patching: re-run
  `codesign --force --deep --sign - <app>` and `codesign --verify --deep --strict <app>`.
  If the copy was moved, re-signing is normally unnecessary but harmless.
- Gatekeeper blocks the copy: `xattr -dr com.apple.quarantine <app>`.

## Agent still behaves like the cloud version

- Confirm the patched copy is the running process:
  `ps -axo pid,command | grep 'CursorLocal.app/Contents/MacOS'`.
- Confirm the variables reached the process:
  `ps eww -p <pid> | tr ' ' '\n' | grep CURSOR_LOCAL_AGENT`.
- Model IDs must exist in the gateway's `/models`. Restart the copy after changing the
  gateway catalog; the picker is cached.
- Tool calling must work. Chat-only endpoints answer once and then the Agent stalls.

## Updates

Any Cursor update replaces the bundle and drops the patch. Always launch with
`--disable-updates`; when the copy does update, rebuild it from the new source app.

## Rollback

Quit the copy, then delete `~/Applications/CursorLocal.app` and
`~/Library/Application Support/CursorLocal`. The main install is untouched. Remove the
`--user-data-dir` copy to drop its stored credentials.
