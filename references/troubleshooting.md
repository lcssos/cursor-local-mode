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
- The script patches five candidate files. If a build adds or renames one, the file is
  reported as "not in this build" and skipped — check that the desktop workbench, the
  Agents Window (`workbench.glass.main.js`) and `extensionHostProcess.js` were all
  listed as patched or already enabled.
- `product.json` has a `checksums` map for a handful of bundle files. The script
  refreshes the entries it can find; a missing key is normal for `main.js` and the
  glass bundle. Do not hand-edit these hashes.
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
- If only the desktop window works and the Agents Window still talks to the cloud,
  `workbench.glass.main.js` was not patched — rebuild from the current source app.

## Persisted environment

`--persist` writes `~/Library/LaunchAgents/local.cursor-local.env.plist` (mode 600).
Any process of the user can still read those variables with `launchctl getenv`, so keep
a placeholder gateway key there rather than a key for a hosted provider. `--forget`
unloads the job, deletes the plist, and unsets both variables.

## Updates

Any Cursor update replaces the bundle and drops the patch. Always launch with
`--disable-updates`; when the copy does update, rebuild it from the new source app.

## Rollback

Quit the copy, then delete `~/Applications/CursorLocal.app` and
`~/Library/Application Support/CursorLocal`. The main install is untouched. Remove the
`--user-data-dir` copy to drop its stored credentials.
