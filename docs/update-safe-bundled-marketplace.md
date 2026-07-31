# Codex Desktop bundled marketplace: update-safe recovery

This note records the Windows failure mode where Codex Desktop updates successfully but Browser, Chrome, or Computer Use still load from an older `openai-bundled` marketplace.

## Conclusion

Current Codex Desktop builds manage `openai-bundled` themselves. The healthy source is a runtime marketplace under the user profile, typically:

```text
%USERPROFILE%\.codex\.tmp\bundled-marketplaces\openai-bundled-appx-<desktop-version>
```

Do not permanently point `config.toml` at either of these locations:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_<version>\...\openai-bundled
%USERPROFILE%\.codex\marketplaces\openai-bundled\<old-version>
```

The first path changes with every AppX update. The second is a manual snapshot that Codex Desktop does not refresh.

The preferred lifecycle is:

1. Codex Desktop reads bundled plugins from its current AppX package.
2. Desktop materializes a runtime marketplace under `.codex\.tmp\bundled-marketplaces`.
3. Desktop registers that runtime path as `openai-bundled` in `config.toml`.
4. Installed plugin cache entries are reconciled against the bundled manifests.

Manual copying is a recovery fallback, not the normal update mechanism.

## Evidence from the 2026-07 incident

The failing machine had these layers out of sync:

| Layer | Observed value |
|---|---|
| Codex Desktop package | `26.707.12708.0` |
| Manually configured marketplace snapshot | `openai-bundled\26.707.3748` |
| Browser/Chrome in that snapshot | `26.707.31428` |
| Browser/Chrome in the current AppX package | `26.707.91948` |

The manually copied snapshot was also EFS-encrypted, while `.codex` and the Desktop-managed runtime workspace were unencrypted. That explained earlier copy failures such as Windows error 6000.

After a later Desktop update, the native reconciler automatically produced:

| Layer | Observed value |
|---|---|
| Codex Desktop package | `26.721.4979.0` |
| Registered marketplace | `openai-bundled-appx-26.721.4979.0` |
| Package Browser/Chrome/Computer Use | `26.721.41059` |
| Runtime Browser/Chrome/Computer Use | `26.721.41059` |

This is the healthy state: the Desktop package version and plugin version do not need to be equal, but each runtime plugin version must match the same plugin manifest in the current package.

## Follow-up incident: Desktop did not materialize the current marketplace

A later update exposed a second failure mode:

| Layer | Observed value |
|---|---|
| Codex Desktop package | `26.727.4816.0` |
| Current bundled Browser/Chrome/Computer Use | `26.727.40816` |
| Registered marketplace before recovery | `openai-bundled-appx-26.721.4979.0` |
| Installed Browser/Chrome/Computer Use records | `26.721.41059` |
| Expected current marketplace | `openai-bundled-appx-26.727.4816.0` |

The current AppX resources existed, but Desktop did not create the expected user-side marketplace after multiple complete restarts. Removing the stale registration correctly exposed the missing current marketplace, but it also made all bundled plugins disappear until a current source was registered. The old marketplace and plugin caches were not deleted; they were simply no longer active.

Recovery required two separate operations:

1. Materialize the current AppX marketplace into the exact AppX-specific user path without propagating Application Protected/EFS attributes.
2. Re-add Browser, Chrome, and Computer Use once from that current marketplace so their installed records and caches moved from `26.721.41059` to `26.727.40816`.

This is a one-time recovery, not a synchronization strategy. Do not turn the `plugin add` commands into a scheduled task.

## Version layers are independent

Do not compare unrelated version numbers as though they are one installation:

| Layer | How to inspect it |
|---|---|
| Codex Desktop AppX | `Get-AppxPackage -Name OpenAI.Codex` |
| Desktop bundled plugin | Read `plugins\<name>\.codex-plugin\plugin.json` inside the AppX package |
| Runtime marketplace | `codex plugin marketplace list` |
| Installed plugin/cache | `codex plugin list` |
| Global CLI | `codex --version` |
| Primary runtime bundle | Read the versions shown for `openai-primary-runtime` plugins |

Updating the global CLI does not update the Desktop AppX runtime. Updating Desktop does not guarantee that a manually pinned marketplace or stale plugin cache was updated.

## Health check

Run the repository script:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-codex-browser-health.ps1
```

It verifies:

- the installed Desktop package and current AppX resource path
- the active `openai-bundled` marketplace root
- Browser, Chrome, and Computer Use versions in both locations
- the installed version of each bundled plugin when that plugin is installed
- whether the active marketplace root is EFS-encrypted
- whether the active source is managed for the current AppX version

The script is read-only. Exit code `0` means the compared layers match; exit code `1` means the output needs attention.

## Normal recovery sequence

Use this order before copying any files:

1. Fully quit Codex Desktop, including background/tray processes.
2. Start the current Desktop build once and wait for plugin reconciliation.
3. Run `codex plugin marketplace list`.
4. Confirm that `openai-bundled` points to the current `openai-bundled-appx-<desktop-version>` directory.
5. Run `codex plugin list` and confirm Browser/Chrome are installed and enabled.
6. Run the health-check script and compare package/runtime manifests.

Useful commands:

```powershell
codex doctor
codex plugin marketplace list
codex plugin list
codex mcp list
codex features list | Select-String -Pattern "plugins|browser_use|in_app_browser|computer_use|remote_control"
```

On current CLI builds, `remote_control` is removed and should not be added to new configurations. Older repository history mentions it because older Browser Use builds depended on it.

## If Desktop does not re-register the marketplace

Back up the configuration first:

```powershell
$config = "$env:USERPROFILE\.codex\config.toml"
Copy-Item -LiteralPath $config -Destination "$config.bak-before-browser-repair-$(Get-Date -Format yyyyMMdd-HHmmss)"
```

Then remove only the stale marketplace registration:

```powershell
codex plugin marketplace remove openai-bundled
```

Fully restart Codex Desktop and let it register the current AppX runtime marketplace. Do not immediately register an old snapshot again.

Removing the registration does not delete old marketplace or cache directories. However, if Desktop still fails to materialize a current source, Browser, Chrome, and Computer Use will be absent from `codex plugin list` until the current marketplace is recovered. Keep the configuration backup and proceed to the last-resort flow below instead of registering the old source again.

If the runtime marketplace remains missing or incomplete, check encryption and permissions:

```powershell
cipher /c "$env:USERPROFILE\.codex"
cipher /c "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces"
```

`U` means unencrypted and `E` means EFS-encrypted. Do not recursively decrypt or delete directories without first confirming the exact target and keeping a configuration backup.

## Stable-path registration: compatibility fallback

Some older Desktop builds used this non-versioned runtime directory:

```text
%USERPROFILE%\.codex\.tmp\bundled-marketplaces\openai-bundled
```

Registering it can help older builds or make bundled plugins visible to a standalone global CLI:

```powershell
codex plugin marketplace remove openai-bundled
codex plugin marketplace add "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled"
```

Use this only after checking its plugin manifests. A directory can exist while still containing an older Desktop generation. New Desktop builds may replace the registration with an `openai-bundled-appx-*` source during startup; that is expected and should be allowed.

## Manual copy: last resort

Only copy from the current AppX package when all of these are true:

- Desktop reconciliation repeatedly fails after a full restart.
- The active runtime marketplace is missing, partial, or has mismatched manifests.
- EFS and file-lock conditions have been checked.
- `config.toml` has been backed up.

Copying directly into plugin caches is fragile because Chrome may hold `extension-host.exe` open. Materialize the marketplace first, validate it, and let `codex plugin add` create versioned caches.

The following pattern was validated during the `26.727.4816.0` incident. It refuses to overwrite an existing target, copies through a unique staging directory, strips encryption attributes, validates every file by relative path and SHA256, and atomically moves the validated tree into place:

```powershell
$ErrorActionPreference = 'Stop'

$appx = Get-AppxPackage -Name OpenAI.Codex |
  Sort-Object Version -Descending |
  Select-Object -First 1

$source = Join-Path $appx.InstallLocation 'app\resources\plugins\openai-bundled'
$parent = Join-Path $env:USERPROFILE '.codex\.tmp\bundled-marketplaces'
$target = Join-Path $parent "openai-bundled-appx-$($appx.Version)"
$staging = Join-Path $parent ('.staging-' + [guid]::NewGuid().ToString('N'))

if (!(Test-Path -LiteralPath $source -PathType Container)) {
  throw "Bundled marketplace source is missing: $source"
}
if (Test-Path -LiteralPath $target) {
  throw "Target already exists; validate it instead of overwriting it: $target"
}

New-Item -ItemType Directory -Path $parent -Force | Out-Null
New-Item -ItemType Directory -Path $staging | Out-Null

& robocopy $source $staging /E /COPY:DAT /DCOPY:DAT /A-:E /R:1 /W:1 /XJ /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -gt 7) {
  throw "robocopy failed with exit code $LASTEXITCODE; staging retained: $staging"
}

$sourceFiles = @(Get-ChildItem -LiteralPath $source -Recurse -Force -File)
$stagedFiles = @(Get-ChildItem -LiteralPath $staging -Recurse -Force -File)
if ($sourceFiles.Count -ne $stagedFiles.Count) {
  throw "File count mismatch; staging retained: $staging"
}

$stagedByRelativePath = @{}
foreach ($file in $stagedFiles) {
  $relativePath = [IO.Path]::GetRelativePath($staging, $file.FullName)
  $stagedByRelativePath[$relativePath] = $file.FullName
}

foreach ($file in $sourceFiles) {
  $relativePath = [IO.Path]::GetRelativePath($source, $file.FullName)
  $stagedPath = $stagedByRelativePath[$relativePath]
  if ($null -eq $stagedPath) {
    throw "Missing staged file: $relativePath"
  }
  if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne
      (Get-FileHash -LiteralPath $stagedPath -Algorithm SHA256).Hash) {
    throw "SHA256 mismatch: $relativePath"
  }
}

$encrypted = @(Get-ChildItem -LiteralPath $staging -Recurse -Force |
  Where-Object { $_.Attributes -band [IO.FileAttributes]::Encrypted })
if ($encrypted.Count -ne 0) {
  throw "Staging contains encrypted entries: $($encrypted.Count)"
}
if (Test-Path -LiteralPath $target) {
  throw "Target appeared during validation; staging retained: $staging"
}

[IO.Directory]::Move($staging, $target)
```

Register the validated marketplace and inspect installed versions:

```powershell
$appx = Get-AppxPackage -Name OpenAI.Codex |
  Sort-Object Version -Descending |
  Select-Object -First 1
$target = Join-Path $env:USERPROFILE ".codex\.tmp\bundled-marketplaces\openai-bundled-appx-$($appx.Version)"

codex plugin marketplace add $target --json
codex plugin marketplace list --json
codex plugin list --available --json
```

If Browser, Chrome, or Computer Use still reports an older installed version, reinstall each one once from the current marketplace:

```powershell
foreach ($plugin in @('computer-use', 'browser', 'chrome')) {
  codex plugin add "$plugin@openai-bundled" --json
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to install $plugin from the recovered marketplace."
  }
}
```

Then fully quit Desktop, including its tray process, and restart it. Desktop still owns Chrome Native Host reconciliation. Do not manually create the registry key or manifest, and do not run the historical `installManifest.mjs` script.

## Other warnings that are not this bug

- `thread/rollback is deprecated` comes from a Desktop/app-server protocol call, not from a `config.toml` marketplace key.
- `Auth: Unsupported` for a stdio MCP server describes its authentication model; it does not mean the server is disabled.
- `TERM=dumb` from `codex doctor` can be caused by a non-interactive diagnostic shell.
- `type = "stdio"` under older MCP entries is no longer required by current config schemas.

## English summary

Let current Codex Desktop builds own the bundled marketplace lifecycle. A healthy installation points `openai-bundled` at the current AppX-specific runtime marketplace under `.codex\.tmp\bundled-marketplaces`; the runtime and installed Browser/Chrome/Computer Use versions match the manifests shipped in the installed AppX package. If Desktop repeatedly fails to materialize that marketplace, use a validated one-time recovery rather than a scheduled synchronization task. Treat a non-versioned stable path as an older-build compatibility fallback and direct cache copying as the last recovery step.
