# Chrome plugin installs but Native Host is missing

This runbook covers a Windows failure where Codex Desktop shows `Failed to install plugin` for Chrome even though the plugin and Chrome extension are present.

## Short conclusion

Do not use a scheduled CLI script to keep `chrome@openai-bundled` installed. `codex plugin add` can create the plugin configuration and cache, but Chrome's Native Messaging Host is owned by Codex Desktop's native reconciliation flow. A scheduled CLI install can therefore leave this split state:

```text
Chrome extension: installed and enabled
Codex plugin:     installed and enabled
Native Host:      missing
UI result:        Failed to install plugin
```

Let Desktop own Chrome installation and Native Host reconciliation. Use CLI commands for diagnosis, not as a recurring Chrome installer.

## Confirmed 2026-07 incident

The affected machine had:

| Layer | Value |
|---|---|
| Desktop AppX | `26.721.4979.0` |
| Bundled Chrome plugin | `26.721.41059` |
| Global CLI before recovery | `0.144.5` |
| Chrome extension | installed and enabled |
| Chrome cache | `chrome\26.721.41059` and `chrome\latest` present |
| Native Host registry key | missing |
| Native Host manifest | missing |

The AppX version, plugin version, CLI version, and primary runtime version are independent layers. They are not expected to have the same number.

The decisive finding was that the current Desktop build expected these version-derived runtime directories, but neither existed:

```text
%LOCALAPPDATA%\OpenAI\Codex\bin\<current-codex-bundle-hash>
%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node\<current-cua-bundle-hash>
```

Only older hash directories remained. The UI successfully completed `plugin/install`, then failed before writing the Native Host manifest and registry key because it could not materialize the current AppX runtime from Application Protected files under WindowsApps.

## Fast red/green signal

The Chrome plugin includes two useful checks:

```powershell
$chrome = "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\chrome\latest"
$node = (Get-Command node).Source

& $node "$chrome\scripts\check-extension-installed.js" --json
& $node "$chrome\scripts\check-native-host-manifest.js" --json
```

The incident reproduced as:

```text
extension check exit code: 0
native host check exit code: 1
problem: registry key and manifest do not exist
```

This is more precise than relying on the UI's generic `Failed to install plugin` message.

## Diagnostic order

### Current Native Host name

Current builds use `com.openai.codexextension`:

```text
HKCU\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension
%LOCALAPPDATA%\OpenAI\extension\com.openai.codexextension.json
```

Checking only the older `com.openai.codex` key produces a false missing-host result on current builds. Prefer the Chrome plugin's generated `check-native-host-manifest.js` because it reads the expected host name and extension origins for that plugin version.

### 1. Check the three independent states

```powershell
codex plugin list --json

Test-Path 'Registry::HKEY_CURRENT_USER\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension'
Test-Path "$env:LOCALAPPDATA\OpenAI\extension\com.openai.codexextension.json"
```

If the plugin is installed but both Native Host checks are false, reinstalling through CLI is not the fix.

### 2. Check the Chrome cache

```powershell
$chromeRoot = "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\chrome"
Get-ChildItem -Force -LiteralPath $chromeRoot |
  Select-Object Name, LinkType, Target, Attributes

Test-Path "$chromeRoot\latest\extension-host\windows\x64\extension-host.exe"
```

Current Desktop code reconciles `latest` to the manifest version. A missing `latest` or host executable is a direct failure, but fixing only this path is insufficient when the Desktop runtime hashes are also missing.

### 3. Check the current AppX runtime materialization

Preview the recovery with PowerShell's standard `-WhatIf` mode:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\repair-codex-chrome-runtime.ps1 -WhatIf
```

`-WhatIf` performs discovery and validation only. It does not create the parent directory, staging directory, or target directory, and it does not run the recovered executables.

Results:

- `healthy`: the exact current hash directory exists and validates.
- `What if: ...`: the current AppX runtime is present in WindowsApps but its validated user-side copy is missing.
- an exception: a required AppX file is missing or an existing target failed validation.

For the Desktop runtime schema validated during this incident, the script hashes these Codex files in order:

```text
codex.exe
codex-code-mode-host.exe
codex-windows-sandbox-setup.exe
codex-command-runner.exe
```

It separately hashes the CUA manifest and the two executable paths declared by that manifest. For the validated build, those inputs are:

```text
manifest.json
bin\node.exe
bin\node_repl.exe
```

## Recovery

First disable any scheduled task that runs `codex plugin add chrome@openai-bundled`. Keep its files for rollback, but do not let it race Desktop startup.

Then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\repair-codex-chrome-runtime.ps1
```

The script:

1. selects the newest installed `OpenAI.Codex` AppX package;
2. computes the exact 16-character runtime hashes expected by Desktop;
3. copies through staging with `robocopy /A-:E` so WindowsApps encryption does not propagate;
4. validates every recursive file by relative path and SHA256, then checks encryption attributes;
5. atomically renames staging into the expected hash directories;
6. smoke-tests `codex.exe`, `node.exe`, and `node_repl.exe`, failing recovery if any process returns a nonzero exit code.

It refuses to overwrite an existing invalid hash directory. Inspect or back up that directory before taking any destructive action.

After recovery, fully quit Codex Desktop, including its tray process, then restart it. Desktop should reconcile the already-installed Chrome plugin and create:

```text
%LOCALAPPDATA%\OpenAI\extension\com.openai.codexextension.json
HKCU\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension
```

Re-run `check-native-host-manifest.js --json`. Success means exit code `0` and `correct: true`.

If the manifest check, extension check, and host executable all pass but browser discovery still reports Chrome as unavailable, check whether Chrome is running before reinstalling anything:

```powershell
$chrome = "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\chrome\latest"
$node = (Get-Command node).Source

& $node "$chrome\scripts\chrome-is-running.js" --browser chrome --check
& $node "$chrome\scripts\check-extension-installed.js" --browser chrome --json
& $node "$chrome\scripts\check-native-host-manifest.js" --browser chrome --json
```

`chrome-is-running` exit code `1` means the browser is closed, not that the plugin is damaged. Start Chrome with the profile selected by the extension check, then retry the live connection. A complete smoke test should cover both surfaces separately: the in-app Browser can be healthy while Chrome is merely not running.

## Do not do these

- Do not keep Chrome installed through a recurring `codex plugin add` task.
- Do not manually write the Native Host registry key or manifest; Desktop owns their schema and runtime metadata.
- Do not run the plugin's historical `installManifest.mjs` by hand. Current Desktop builds use a newer native reconciliation implementation.
- Do not copy files into WindowsApps or modify the AppX package.
- Do not assume a newer global npm CLI repairs Desktop's embedded runtime.
- Do not delete all old hash directories until the current runtime is validated and Desktop has restarted successfully.

## Compatibility boundary

No output directory hash is hard-coded: every run derives its source from the newest installed AppX and calculates target hashes from that package's files. The CUA executable paths come from the AppX runtime manifest.

The Codex hash input set is the schema confirmed for Desktop `26.721.4979.0`; it is not a guarantee for every future Desktop build. A missing required file or an incompatible CUA manifest fails closed. After a Desktop update, run `-WhatIf` first and confirm that the documented hash inputs still match the new bundle before performing recovery.

The repair remains a fallback. A healthy Desktop should materialize these runtimes itself.

## English summary

If Chrome is installed in Codex and the browser extension is enabled, but both the Native Host registry key and manifest are missing, do not repeatedly reinstall Chrome through the CLI. Check whether the current Desktop AppX runtime hashes were materialized under `%LOCALAPPDATA%\OpenAI\Codex`. Use the repository repair script to create only validated runtime copies, then restart Desktop and let its native reconciler own the manifest and registry registration.
