# Codex Browser Use Fix

[中文](#中文) | [English](#english) | [Update-safe marketplace](./docs/update-safe-bundled-marketplace.md) | [Chrome Native Host repair](./docs/chrome-native-host-runtime-repair.md) | [Health check](./scripts/check-codex-browser-health.ps1) | [Runtime repair](./scripts/repair-codex-chrome-runtime.ps1) | [HTML guide](./browser-use-plugin-tutorial.html)

This repository documents Windows workarounds for repairing Codex Desktop's bundled browser plugins when they are present locally but unavailable or broken in the plugin UI. It covers the in-app `Browser` plugin and the external `Chrome` plugin.

All examples are sanitized. Replace placeholders such as `<Codex install directory>`, `<version>`, and `%USERPROFILE%` with values from your own machine.

## 中文

这份教程用于修复 Codex Desktop 更新后 `Browser Use` / `Browser` / `Chrome` 消失、插件页能看到但安装失败、或 `codex debug prompt-input` 无法加载插件的问题。

当前版本的首选方案是让 Codex Desktop 自动把 AppX 包内的 `openai-bundled` 同步到 `%USERPROFILE%\.codex\.tmp\bundled-marketplaces\openai-bundled-appx-<desktop-version>`，并由 Desktop 自动注册该运行时路径。不要长期指向 WindowsApps 安装目录，也不要把手工复制的旧快照当成正常更新源。

如果 Desktop 多次完整重启后仍没有生成当前 AppX 专用市场，或市场已经更新但 `codex plugin list --json` 仍显示旧版 Browser/Chrome/Computer Use，请使用 [Update-safe bundled marketplace](./docs/update-safe-bundled-marketplace.md#follow-up-incident-desktop-did-not-materialize-the-current-marketplace) 中的一次性恢复流程。该流程使用暂存目录、去除加密属性、全量 SHA256 校验和原子落位；恢复后只执行一次 `plugin add`，不要创建自动同步任务。

本次完整经验、版本分层、EFS 诊断和恢复顺序见 [Update-safe bundled marketplace](./docs/update-safe-bundled-marketplace.md)。可以先运行只读检查：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-codex-browser-health.ps1
```

如果 Chrome 扩展已经启用、插件也显示已安装，但 UI 仍提示 `Failed to install plugin`，并且 Native Host 注册表与 manifest 都不存在，请使用 [Chrome Native Host runtime repair](./docs/chrome-native-host-runtime-repair.md)。不要用计划任务反复执行 `codex plugin add chrome@openai-bundled`；CLI 安装插件不等于 Desktop 已完成 Native Host reconcile。

当前 Chrome Native Host 名称是 `com.openai.codexextension`。只检查旧键 `com.openai.codex` 会产生误报；优先运行 Chrome 插件自带的 `check-native-host-manifest.js`。如果扩展、manifest 和宿主程序均正确但 Chrome 控制仍不可用，先确认 Chrome 是否正在运行。

如果浏览器能力又突然失效，先运行健康检查并比较 AppX 与 runtime manifest。只有旧版 `Browser Use` 流程依赖 `remote_control`；当前 `Browser` / `Chrome` 插件不应再添加这个已移除的 feature。

### 适用场景

- Windows 上使用 Codex Desktop。
- 本地 Codex 安装目录包含 `openai-bundled\plugins\browser-use`。
- 新版 Codex 安装目录包含 `openai-bundled\plugins\browser`，但用户侧 `browser\latest` cache 缺失。
- 更新 Codex 后 `Browser Use` 消失。
- 插件页能看到 `Browser Use`，但点击安装失败。
- 日志或调试输出显示 `plugin is not installed`。
- `codex debug prompt-input` 不再显示 `browser-use:browser`。
- `codex debug prompt-input` 不再显示 `browser:browser`。
- `codex debug prompt-input` 不再显示 `chrome:Chrome`。
- `@chrome` 已在配置中启用，但运行时连不上 Chrome 或缺少 `node_repl` helper。

### 2026-07 更新：先让 Desktop 原生同步

新版 Desktop 会自动维护 AppX 专用 runtime marketplace。例如 Desktop `26.721.4979.0` 会注册类似下面的路径：

```text
%USERPROFILE%\.codex\.tmp\bundled-marketplaces\openai-bundled-appx-26.721.4979.0
```

健康状态不是“目录名永远不变”，而是 `codex plugin marketplace list` 指向当前 Desktop 生成的 runtime marketplace，并且其中 Browser/Chrome/Computer Use 的 manifest 版本与当前 AppX 包一致。

如果配置仍指向 `%USERPROFILE%\.codex\marketplaces\openai-bundled\<旧版本>`，先备份配置、移除旧注册并完整重启 Desktop。不要立即把旧快照注册回来：

```powershell
codex plugin marketplace remove openai-bundled
```

当前 CLI 已移除 `remote_control` feature。新配置不要再添加 `remote_control = true`；README 后面的相关命令只适用于历史 `browser-use` 插件恢复。

### 旧版兼容：marketplace 还在但 Browser Use 又失效

> 本节仅适用于仍随包提供 `browser-use`、且 `codex features list` 仍列出 `remote_control` 的旧版 Codex。当前版本请使用上面的 Desktop 原生同步流程。

如果下面路径存在：

```text
%USERPROFILE%\.codex\.tmp\bundled-marketplaces\openai-bundled\plugins\browser-use
```

可以直接运行这个恢复脚本。它会动态读取插件版本号，补齐 cache，并把必需配置写回 `config.toml`：

```powershell
$ErrorActionPreference = "Stop"

$marketplace = "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled"
$pluginSrc = Join-Path $marketplace "plugins\browser-use"
$manifestPath = Join-Path $pluginSrc ".codex-plugin\plugin.json"
$configPath = "$env:USERPROFILE\.codex\config.toml"

if (!(Test-Path -LiteralPath $manifestPath)) {
  throw "browser-use manifest not found: $manifestPath"
}

$version = (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).version
$cacheDst = "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\browser-use\$version"

New-Item -ItemType Directory -Force -Path $cacheDst | Out-Null

$srcRoot = (Resolve-Path -LiteralPath $pluginSrc).Path.TrimEnd('\')
$dstRoot = (Resolve-Path -LiteralPath $cacheDst).Path.TrimEnd('\')

Get-ChildItem -LiteralPath $srcRoot -Force -Recurse -Directory | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
  New-Item -ItemType Directory -Force -Path (Join-Path $dstRoot $rel) | Out-Null
}

Get-ChildItem -LiteralPath $srcRoot -Force -Recurse -File | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
  $target = Join-Path $dstRoot $rel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
  [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($_.FullName))
}

$config = Get-Content -LiteralPath $configPath -Raw

if ($config -notmatch '(?m)^\[marketplaces\.openai-bundled\]') {
  Add-Content -LiteralPath $configPath -Value @"

[marketplaces.openai-bundled]
source_type = "local"
source = '\\?\$marketplace'
"@
}

if ($config -notmatch '(?m)^\[plugins\."browser-use@openai-bundled"\]') {
  Add-Content -LiteralPath $configPath -Value @'

[plugins."browser-use@openai-bundled"]
enabled = true
'@
}

$features = codex features list
if ($features | Select-String -Pattern "^remote_control\s") {
  codex features enable remote_control
}
$features | Select-String -Pattern "remote_control|browser_use|in_app_browser|computer_use|plugins"
codex debug prompt-input "test browser use" | Select-String -Pattern "browser-use:browser|Browser Use|failed to load plugin|plugin is not installed"
```

恢复后重启 Codex Desktop。

### 最后恢复：Browser / Chrome 插件 cache 过期

以下手工同步只在 Desktop 多次完整重启后仍无法生成匹配当前 AppX 的 runtime marketplace 时使用。

Codex Desktop 更新后，安装包中的 `browser` / `chrome` 插件版本可能变成类似 `26.519.41501` 的版本。如果用户目录里的 marketplace 或 cache 仍是旧版本，`@browser` / `@chrome` 可能加载到过期插件代码。新版内置浏览器插件名通常是 `browser@openai-bundled`，不是旧的 `browser-use@openai-bundled`。

先查看当前安装包里的真实版本：

```powershell
$package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
$browserPlugin = Join-Path $package.InstallLocation "app\resources\plugins\openai-bundled\plugins\browser"
$chromePlugin = Join-Path $package.InstallLocation "app\resources\plugins\openai-bundled\plugins\chrome"
Get-Content (Join-Path $browserPlugin ".codex-plugin\plugin.json") -Raw
Get-Content (Join-Path $chromePlugin ".codex-plugin\plugin.json") -Raw
```

再把最新版插件同步到用户侧 marketplace 和 plugin cache。这个脚本只复制 `browser` / `chrome` 插件目录，不重写整个 `config.toml`，也不会先删除 `latest`。如果 `chrome\latest\extension-host\windows\x64\extension-host.exe` 正被 Chrome 占用，脚本会跳过哈希一致的文件，避免把 cache 留在半删除状态：

```powershell
$ErrorActionPreference = "Stop"

$package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1

function Get-Sha256Hex {
  param([Parameter(Mandatory = $true)][string]$Path)
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Sync-TreeByHash {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $srcRoot = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\')
  $dstRoot = (Resolve-Path -LiteralPath $Destination).Path.TrimEnd('\')
  $failed = @()

  Get-ChildItem -LiteralPath $srcRoot -Force -Recurse -Directory | ForEach-Object {
    $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
    New-Item -ItemType Directory -Force -Path (Join-Path $dstRoot $rel) | Out-Null
  }

  Get-ChildItem -LiteralPath $srcRoot -Force -Recurse -File | ForEach-Object {
    $sourcePath = $_.FullName
    $rel = $sourcePath.Substring($srcRoot.Length).TrimStart('\')
    $target = Join-Path $dstRoot $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null

    $sameHash = $false
    if (Test-Path -LiteralPath $target) {
      try {
        $sameHash = (Get-Sha256Hex $sourcePath) -eq (Get-Sha256Hex $target)
      } catch {
        $sameHash = $false
      }
    }

    if (-not $sameHash) {
      try {
        [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($sourcePath))
      } catch {
        $failed += [pscustomobject]@{ source = $sourcePath; target = $target; error = $_.Exception.Message }
      }
    }
  }

  if ($failed.Count -gt 0) {
    $failed | ConvertTo-Json -Depth 4
    throw "Failed to sync $($failed.Count) file(s). Close Chrome/Codex and rerun if hashes differ."
  }
}

foreach ($plugin in @("browser", "chrome")) {
  $pluginSrc = Join-Path $package.InstallLocation "app\resources\plugins\openai-bundled\plugins\$plugin"
  $manifestPath = Join-Path $pluginSrc ".codex-plugin\plugin.json"

  if (!(Test-Path -LiteralPath $manifestPath)) {
    Write-Warning "Skipped missing package plugin: $plugin"
    continue
  }

  $version = (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).version
  Sync-TreeByHash -Source $pluginSrc -Destination "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled\plugins\$plugin"
  Sync-TreeByHash -Source $pluginSrc -Destination "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\$plugin\$version"
  Sync-TreeByHash -Source $pluginSrc -Destination "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\$plugin\latest"
}

codex features list | Select-String -Pattern "plugins|browser_use|in_app_browser|computer_use"
codex debug prompt-input "test browser and chrome plugins" | Select-String -Pattern "browser:browser|chrome:Chrome|failed to load plugin|plugin is not installed"
```

确认 `config.toml` 里保留这些配置：

```toml
[marketplaces.openai-bundled]
source_type = "local"
source = "\\?\<用户目录>\.codex\.tmp\bundled-marketplaces\openai-bundled"

[plugins."chrome@openai-bundled"]
enabled = true

[plugins."browser@openai-bundled"]
enabled = true

```

不要用会整体 `Set-Content` 重写 `config.toml` 的脚本处理包含中文路径的配置。PowerShell 编码不一致时，`[projects.'d:\中文路径']` 这类表头可能被写成乱码，导致 Codex 报 TOML parse error。修改配置前至少先备份，并在修改后验证：

```powershell
Copy-Item "$env:USERPROFILE\.codex\config.toml" "$env:USERPROFILE\.codex\config.toml.bak-before-browser-plugin-repair" -Force

@'
import pathlib, tomllib
p = pathlib.Path.home() / ".codex" / "config.toml"
tomllib.loads(p.read_text(encoding="utf-8-sig"))
print("config toml ok")
'@ | python -
```

### 高级恢复：Chrome helper binary 过期

如果 `chrome` 插件版本已经更新，但 `@chrome` 仍无法启动，继续检查 helper binary。Codex 会把 `node.exe`、`node_repl.exe`、`rg.exe`、`codex.exe` 等 helper 放到 `%LOCALAPPDATA%\OpenAI\Codex\bin\<hash>`。Codex 更新后，hash 目录可能变化，旧 helper 会失效。

先做 dry-run 检查。下面路径来自本仓库外的本地修复 skill；如果你没有这个 skill，可以按同样原则检查目标 hash 目录是否缺失：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\fix-skill\scripts\repair-codex-windows-browser-use.ps1" -DryRun
```

如果输出里出现 `would-copy`，说明需要修复：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\fix-skill\scripts\repair-codex-windows-browser-use.ps1"
```

修复后再次 dry-run，应看到所有文件都是 `skipped` 且 `sameHash = true`。一次成功修复通常会验证：

```text
node.exe      v24.x
codex.exe     codex-cli <current version>
node_repl.exe Run the node_repl MCP stdio server.
rg.exe        ripgrep <current version>
```

最后完整退出并重启 Codex Desktop，再新开线程测试 `@chrome`。当前线程的工具列表通常不会在运行中完整刷新。

### Chrome 扩展通道连通性测试

`@chrome` 依赖用户 Chrome 里的 Codex 扩展和 native messaging host。修复 cache 和 helper 后，如果扩展通道仍没有出现，先确认 Chrome 是用正确 profile 启动的。Profile 名包含空格时必须给参数值加引号：

```powershell
Start-Process -FilePath "C:\Program Files\Google\Chrome\Application\chrome.exe" -ArgumentList '--profile-directory="Profile 1" --new-window about:blank'
```

不要写成 `--profile-directory=Profile 1`，否则 Chrome 可能把它解析成错误 profile，`agent.browsers.list()` 里只看到 in-app Browser，看不到 `type = extension` 的 Chrome backend。`check-extension-installed.js --json` 里的 `selectedProfileDirectory` 可能来自 Chrome Local State，不一定等于当前进程实际 profile；最终以扩展 backend metadata 和真实导航结果为准。

一次完整验证应至少包含：

```text
codex debug prompt-input "test browser and chrome plugins"
browser:browser -> ...\plugins\cache\openai-bundled\browser\latest\skills\browser\SKILL.md
chrome:Chrome  -> ...\plugins\cache\openai-bundled\chrome\latest\skills\chrome\SKILL.md

Browser opens https://example.com/ -> title "Example Domain"
Chrome extension opens https://example.com/ -> title "Example Domain"
```

### 1. 确认 browser-use 插件存在

先确认当前 Codex Desktop 安装目录里有 bundled 插件：

```text
<Codex安装目录>\app\resources\plugins\openai-bundled\plugins\browser-use
```

PowerShell:

```powershell
$browserUsePath = "<Codex安装目录>\app\resources\plugins\openai-bundled\plugins\browser-use"
Test-Path $browserUsePath
```

返回 `True` 才能继续。

### 2. 读取插件版本号

读取插件 manifest：

```powershell
Get-Content "$browserUsePath\.codex-plugin\plugin.json"
```

找到版本号，例如：

```json
{
  "name": "browser-use",
  "version": "0.1.0-alpha2"
}
```

后续命令里的 `$version` 要使用这个 manifest 中的实际版本，不要照抄示例版本号。

### 3. 兼容方案：固定 openai-bundled marketplace 路径

以下步骤用于旧版 Desktop 或原生同步反复失败的机器，不是新版 Desktop 的默认更新方式。不要长期注册带 Codex 版本号的 WindowsApps 安装目录，例如：

```text
<Codex安装目录>\app\resources\plugins\openai-bundled
```

Codex 更新后这个目录名通常会变化。旧版兼容路径是：

```text
%USERPROFILE%\.codex\.tmp\bundled-marketplaces\openai-bundled
```

PowerShell:

```powershell
$src = "<Codex安装目录>\app\resources\plugins\openai-bundled"
$dst = "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled"

New-Item -ItemType Directory -Force -Path $dst | Out-Null

$srcRoot = (Resolve-Path -LiteralPath $src).Path.TrimEnd('\')
$dstRoot = (Resolve-Path -LiteralPath $dst).Path.TrimEnd('\')

Get-ChildItem -LiteralPath $srcRoot -Force -Recurse -Directory | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
  New-Item -ItemType Directory -Force -Path (Join-Path $dstRoot $rel) | Out-Null
}

Get-ChildItem -LiteralPath $srcRoot -Force -Recurse -File | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
  $target = Join-Path $dstRoot $rel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
  [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($_.FullName))
}
```

这里使用二进制读写复制，而不是普通 `Copy-Item -Recurse`，是为了避开 WindowsApps 等目录可能带来的特殊文件属性问题。执行前先确认当前 Desktop 没有生成可用的 `openai-bundled-appx-*` runtime marketplace。

### 4. 旧版兼容：重新注册 marketplace

如果之前已经注册过 `openai-bundled`，先移除旧注册：

```powershell
codex plugin marketplace remove openai-bundled
```

然后注册固定路径：

```powershell
codex plugin marketplace add "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled"
```

注册后，`%USERPROFILE%\.codex\config.toml` 中应类似：

```toml
[marketplaces.openai-bundled]
source_type = "local"
source = "\\?\<用户目录>\.codex\.tmp\bundled-marketplaces\openai-bundled"
```

重点是 source 不再指向带版本号的 Codex 安装目录。

### 5. 旧版兼容：启用 Browser Use 所需配置

只有 `codex features list` 仍列出 `remote_control` 时才开启：

```powershell
codex features enable remote_control
```

确认 `config.toml` 里有：

```toml
[plugins."browser-use@openai-bundled"]
enabled = true

[features]
remote_control = true
```

如果缺少插件配置，手动追加：

```powershell
Add-Content -LiteralPath "$env:USERPROFILE\.codex\config.toml" -Value @'

[plugins."browser-use@openai-bundled"]
enabled = true
'@
```

### 6. 如安装失败，补齐插件 cache

正常 cache 结构是：

```text
%USERPROFILE%\.codex\plugins\cache\openai-bundled\browser-use\<version>
```

如果这个目录缺少 `.codex-plugin\plugin.json`，可以从固定 marketplace 复制：

```powershell
$version = (Get-Content "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled\plugins\browser-use\.codex-plugin\plugin.json" -Raw | ConvertFrom-Json).version
$src = "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled\plugins\browser-use"
$dst = "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\browser-use\$version"

New-Item -ItemType Directory -Force -Path $dst | Out-Null

$srcRoot = (Resolve-Path -LiteralPath $src).Path.TrimEnd('\')
$dstRoot = (Resolve-Path -LiteralPath $dst).Path.TrimEnd('\')

Get-ChildItem -LiteralPath $srcRoot -Force -Recurse -Directory | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
  New-Item -ItemType Directory -Force -Path (Join-Path $dstRoot $rel) | Out-Null
}

Get-ChildItem -LiteralPath $srcRoot -Force -Recurse -File | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
  $target = Join-Path $dstRoot $rel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
  [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($_.FullName))
}
```

### 7. 验证

检查 feature：

```powershell
codex features list | Select-String -Pattern "remote_control|browser_use|in_app_browser|computer_use|plugins"
```

检查 Codex 是否能加载插件：

```powershell
codex debug prompt-input "test browser use" | Select-String -Pattern "browser-use|Browser Use|failed to load plugin|plugin is not installed"
```

看到 `browser-use:browser` 或 `Browser Use`，并且没有 `failed to load plugin`，说明恢复成功。

最后彻底重启 Codex Desktop。

### 中文 FAQ

**为什么更新后会掉？**

因为 Codex 更新后安装目录名会变化。如果 `config.toml` 里的 marketplace source 指向旧安装目录，Codex 就找不到 bundled marketplace。

**为什么使用 `.codex\.tmp\bundled-marketplaces`？**

这是 Codex Desktop 自己物化 bundled marketplace 的工作区。新版通常使用 `openai-bundled-appx-<desktop-version>`，旧版可能使用无版本目录；应以 `codex plugin marketplace list` 的当前注册为准。

**使用 `.tmp` 有什么风险？**

`.tmp` 会被 Codex 清理或重建，这是正常生命周期。先完整重启 Desktop 让它重新生成；只有自动同步持续失败时，才使用手工复制和 `plugin marketplace add` 兼容方案。

**为什么示例版本号会变化？**

这只是示例版本。真实版本以 `.codex-plugin\plugin.json` 中的 `version` 为准。Codex cache 使用 `<marketplace>\<plugin>\<version>` 结构，所以目录名必须匹配 manifest。

## English

This guide fixes cases where Codex Desktop's bundled `Browser` or `Chrome` plugin disappears after an update, appears in the plugin UI but fails to install, or cannot be loaded by `codex debug prompt-input`.

Current Codex Desktop builds should own the `openai-bundled` lifecycle. Desktop materializes an AppX-specific runtime marketplace under `%USERPROFILE%\.codex\.tmp\bundled-marketplaces` and registers it automatically. Treat a non-versioned mirror as an older-build compatibility fallback, not the primary update mechanism.

If browser support breaks again, run the health check and compare AppX and runtime manifests first. Only the legacy `Browser Use` flow depended on `remote_control`; current Browser and Chrome plugins must not add this removed feature.

If the Chrome extension and Codex plugin are installed but the Native Host registry key and manifest are both missing, follow [Chrome Native Host runtime repair](./docs/chrome-native-host-runtime-repair.md). Do not use a scheduled `codex plugin add chrome@openai-bundled` job: CLI installation does not replace Desktop's Native Host reconciliation.

### When to use this

- You use Codex Desktop on Windows.
- Your local Codex installation contains `openai-bundled\plugins\browser-use`.
- Newer Codex builds contain `openai-bundled\plugins\browser`, but the user-side `browser\latest` cache is missing.
- `Browser Use` disappeared after a Codex update.
- The plugin UI shows `Browser Use`, but installation fails.
- Debug logs mention `plugin is not installed`.
- `codex debug prompt-input` no longer lists `browser-use:browser`.
- `codex debug prompt-input` no longer lists `browser:browser`.
- `codex debug prompt-input` no longer lists `chrome:Chrome`.
- `@chrome` is enabled in config but cannot connect or cannot start its `node_repl` helper.

### Legacy compatibility: marketplace exists but Browser Use broke again

Use this section only when the installed Codex build still ships `browser-use` and `codex features list` still includes `remote_control`.

If this path exists:

```text
%USERPROFILE%\.codex\.tmp\bundled-marketplaces\openai-bundled\plugins\browser-use
```

rebuild the cache and config using the same recovery script from the Chinese section. The important parts are:

- read `version` from `.codex-plugin\plugin.json`
- copy `plugins\browser-use` into `%USERPROFILE%\.codex\plugins\cache\openai-bundled\browser-use\<version>`
- keep `[plugins."browser-use@openai-bundled"] enabled = true`
- enable `remote_control` only when that feature is still listed by the old CLI

### Last-resort recovery: stale Browser / Chrome plugin cache

After a Codex Desktop update, the bundled `browser` / `chrome` plugin version can change to a package-derived version such as `26.519.41501`. If the user-side marketplace or plugin cache still contains the older version, `@browser` / `@chrome` can load stale plugin code. Newer in-app browser builds normally use `browser@openai-bundled`, not the older `browser-use@openai-bundled`.

Check the installed package version:

```powershell
$package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
$browserPlugin = Join-Path $package.InstallLocation "app\resources\plugins\openai-bundled\plugins\browser"
$chromePlugin = Join-Path $package.InstallLocation "app\resources\plugins\openai-bundled\plugins\chrome"
Get-Content (Join-Path $browserPlugin ".codex-plugin\plugin.json") -Raw
Get-Content (Join-Path $chromePlugin ".codex-plugin\plugin.json") -Raw
```

Then copy those plugins into both the bundled marketplace mirror and the plugin cache. Prefer a hash-aware copy-over script that does not delete `latest` first and does not rewrite the whole `config.toml`; rewriting the full file with the wrong PowerShell encoding can corrupt project table names that contain non-ASCII paths. This matters for `chrome\latest`, because `extension-host.exe` can be locked while Chrome is running.

The expected cache paths are:

```text
%USERPROFILE%\.codex\plugins\cache\openai-bundled\browser\<version>
%USERPROFILE%\.codex\plugins\cache\openai-bundled\browser\latest
%USERPROFILE%\.codex\plugins\cache\openai-bundled\chrome\<version>
%USERPROFILE%\.codex\plugins\cache\openai-bundled\chrome\latest
```

Keep this configuration:

```toml
[plugins."chrome@openai-bundled"]
enabled = true

[plugins."browser@openai-bundled"]
enabled = true

```

After editing config, verify it still parses:

```powershell
@'
import pathlib, tomllib
p = pathlib.Path.home() / ".codex" / "config.toml"
tomllib.loads(p.read_text(encoding="utf-8-sig"))
print("config toml ok")
'@ | python -
```

### Advanced recovery: stale Chrome helper binaries

If the `chrome` plugin is current but `@chrome` still cannot start, inspect helper binaries under:

```text
%LOCALAPPDATA%\OpenAI\Codex\bin\<hash>
```

Codex updates can change the hash directories for `codex.exe`, `node_repl.exe`, `node.exe`, and `rg.exe`. A dry run from a helper repair script should show whether files would be copied. If it reports `would-copy`, repair the helpers and rerun dry-run until every file is `skipped` with `sameHash = true`.

The successful validation normally includes:

```text
node.exe      v24.x
codex.exe     codex-cli <current version>
node_repl.exe Run the node_repl MCP stdio server.
rg.exe        ripgrep <current version>
```

Fully quit and restart Codex Desktop after repairing `@chrome`; the current thread usually will not reload the tool list in place.

### Chrome extension channel validation

`@chrome` requires the user's Chrome profile, the Codex Chrome extension, and the native messaging host. If the extension backend still does not appear after cache and helper repair, launch Chrome with the exact profile and quote profile names that contain spaces:

```powershell
Start-Process -FilePath "C:\Program Files\Google\Chrome\Application\chrome.exe" -ArgumentList '--profile-directory="Profile 1" --new-window about:blank'
```

Do not use `--profile-directory=Profile 1`; Chrome may parse it as the wrong profile and the automation agent may only see the in-app Browser backend. Treat `check-extension-installed.js --json` `selectedProfileDirectory` as a Local State hint, not proof of the current process profile.

A complete validation should show:

```text
codex debug prompt-input "test browser and chrome plugins"
browser:browser -> ...\plugins\cache\openai-bundled\browser\latest\skills\browser\SKILL.md
chrome:Chrome  -> ...\plugins\cache\openai-bundled\chrome\latest\skills\chrome\SKILL.md

Browser opens https://example.com/ -> title "Example Domain"
Chrome extension opens https://example.com/ -> title "Example Domain"
```

### 1. Confirm that browser-use exists

Check that the bundled plugin exists:

```text
<Codex install directory>\app\resources\plugins\openai-bundled\plugins\browser-use
```

PowerShell:

```powershell
$browserUsePath = "<Codex install directory>\app\resources\plugins\openai-bundled\plugins\browser-use"
Test-Path $browserUsePath
```

Continue only if it returns `True`.

### 2. Read the plugin version

Read the plugin manifest:

```powershell
Get-Content "$browserUsePath\.codex-plugin\plugin.json"
```

Look for the version:

```json
{
  "name": "browser-use",
  "version": "0.1.0-alpha2"
}
```

Use the actual manifest version in later commands. Do not copy the sample version blindly.

### 3. Compatibility fallback: mirror openai-bundled to the bundled marketplace workspace

This section applies to older Desktop builds or repeated native reconciliation failures. Current builds should use the AppX-specific runtime marketplace that Desktop registers automatically.

Avoid permanently registering the versioned Codex install path:

```text
<Codex install directory>\app\resources\plugins\openai-bundled
```

That path changes after updates. Instead, mirror it here:

```text
%USERPROFILE%\.codex\.tmp\bundled-marketplaces\openai-bundled
```

PowerShell:

```powershell
$src = "<Codex install directory>\app\resources\plugins\openai-bundled"
$dst = "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled"

New-Item -ItemType Directory -Force -Path $dst | Out-Null

$srcRoot = (Resolve-Path -LiteralPath $src).Path.TrimEnd('\')
$dstRoot = (Resolve-Path -LiteralPath $dst).Path.TrimEnd('\')

Get-ChildItem -LiteralPath $srcRoot -Force -Recurse -Directory | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
  New-Item -ItemType Directory -Force -Path (Join-Path $dstRoot $rel) | Out-Null
}

Get-ChildItem -LiteralPath $srcRoot -Force -Recurse -File | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
  $target = Join-Path $dstRoot $rel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
  [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($_.FullName))
}
```

The script copies file bytes directly instead of using plain `Copy-Item -Recurse`, which avoids special file-attribute issues in some Windows install directories.

### 4. Legacy compatibility: re-register the stable marketplace

If `openai-bundled` is already registered, remove the old source first:

```powershell
codex plugin marketplace remove openai-bundled
```

Then register the stable path:

```powershell
codex plugin marketplace add "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled"
```

After that, `%USERPROFILE%\.codex\config.toml` should contain something like:

```toml
[marketplaces.openai-bundled]
source_type = "local"
source = "\\?\<user directory>\.codex\.tmp\bundled-marketplaces\openai-bundled"
```

The important part is that source no longer points to the versioned Codex install directory.

### 5. Legacy compatibility: enable Browser Use settings

For legacy `browser-use` builds only, enable `remote_control` if it is still listed by `codex features list`:

```powershell
codex features enable remote_control
```

Confirm that `config.toml` contains:

```toml
[plugins."browser-use@openai-bundled"]
enabled = true

[features]
remote_control = true
```

If the plugin block is missing, append it:

```powershell
Add-Content -LiteralPath "$env:USERPROFILE\.codex\config.toml" -Value @'

[plugins."browser-use@openai-bundled"]
enabled = true
'@
```

### 6. If installation fails, populate the plugin cache

The expected cache layout is:

```text
%USERPROFILE%\.codex\plugins\cache\openai-bundled\browser-use\<version>
```

If `.codex-plugin\plugin.json` is missing there, copy from the stable marketplace:

```powershell
$version = (Get-Content "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled\plugins\browser-use\.codex-plugin\plugin.json" -Raw | ConvertFrom-Json).version
$src = "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled\plugins\browser-use"
$dst = "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\browser-use\$version"

New-Item -ItemType Directory -Force -Path $dst | Out-Null

$srcRoot = (Resolve-Path -LiteralPath $src).Path.TrimEnd('\')
$dstRoot = (Resolve-Path -LiteralPath $dst).Path.TrimEnd('\')

Get-ChildItem -LiteralPath $srcRoot -Force -Recurse -Directory | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
  New-Item -ItemType Directory -Force -Path (Join-Path $dstRoot $rel) | Out-Null
}

Get-ChildItem -LiteralPath $srcRoot -Force -Recurse -File | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
  $target = Join-Path $dstRoot $rel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
  [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($_.FullName))
}
```

### 7. Verify

Check feature flags:

```powershell
codex features list | Select-String -Pattern "remote_control|browser_use|in_app_browser|computer_use|plugins"
```

Check whether Codex can load the plugin:

```powershell
codex debug prompt-input "test browser use" | Select-String -Pattern "browser-use|Browser Use|failed to load plugin|plugin is not installed"
```

If you see `browser-use:browser` or `Browser Use`, and no `failed to load plugin`, the plugin is loaded.

Finally, fully restart Codex Desktop.

### English FAQ

**Why does it break after updating Codex?**

Codex updates can change the versioned installation directory. If `config.toml` points to the old marketplace source, Codex can no longer find the bundled marketplace.

**Why use `.codex\.tmp\bundled-marketplaces`?**

It is still under the user profile, so it avoids versioned install paths. It is also closer to Codex's own bundled marketplace workspace, so future Codex updates are more likely to refresh it with newer bundled content.

**What is the risk of using `.tmp`?**

`.tmp` may be cleaned or rebuilt by Codex as part of its normal lifecycle. Fully restart Desktop and allow native reconciliation first; copy and register a marketplace manually only if that repeatedly fails.

**Why does the sample version change?**

That is only a sample value. Use the version declared by the plugin manifest. Codex stores cache entries as `<marketplace>\<plugin>\<version>`, so the cache directory must match the manifest.

## HTML version

A standalone HTML version of this guide is included here:

[browser-use-plugin-tutorial.html](./browser-use-plugin-tutorial.html)
