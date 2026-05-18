# Codex Browser Use Fix

[中文](#中文) | [English](#english) | [HTML guide](./browser-use-plugin-tutorial.html)

This repository documents a Windows workaround for enabling Codex Desktop's bundled `Browser Use` plugin when it is present locally but unavailable or broken in the plugin UI.

All examples are sanitized. Replace placeholders such as `<Codex install directory>`, `<version>`, and `%USERPROFILE%` with values from your own machine.

## 中文

这份教程用于修复 Codex Desktop 更新后 `Browser Use` 消失、插件页能看到但安装失败、或 `codex debug prompt-input` 无法加载插件的问题。

推荐方案是把 `openai-bundled` marketplace 复制到 Codex 的 bundled marketplace 工作区，然后让 Codex 注册这个相对稳定的用户侧路径。这样 Codex 更新后，即使安装目录里的版本号变化，`Browser Use` 也不会因为 marketplace source 指向旧安装路径而失效。

如果固定 marketplace 还在，但 `Browser Use` 又突然失效，优先检查插件 cache 和配置项。近期常见原因是 `%USERPROFILE%\.codex\plugins\cache\openai-bundled\browser-use` 被清理，或 `config.toml` 里丢失了 `browser-use@openai-bundled` / `remote_control`。

### 适用场景

- Windows 上使用 Codex Desktop。
- 本地 Codex 安装目录包含 `openai-bundled\plugins\browser-use`。
- 更新 Codex 后 `Browser Use` 消失。
- 插件页能看到 `Browser Use`，但点击安装失败。
- 日志或调试输出显示 `plugin is not installed`。
- `codex debug prompt-input` 不再显示 `browser-use:browser`。

### 快速恢复：marketplace 还在但 Browser Use 又失效

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

$config = Get-Content -LiteralPath $configPath -Raw

if ($config -match '(?m)^\[features\]') {
  if ($config -notmatch '(?m)^remote_control\s*=') {
    $config = $config -replace '(?m)^\[features\]\s*$', "[features]`nremote_control = true"
  } else {
    $config = $config -replace '(?m)^remote_control\s*=.*$', 'remote_control = true'
  }

  Set-Content -LiteralPath $configPath -Value $config -NoNewline
} else {
  Add-Content -LiteralPath $configPath -Value @'

[features]
remote_control = true
'@
}

codex features enable remote_control
codex features list | Select-String -Pattern "remote_control|browser_use|in_app_browser|computer_use|plugins"
codex debug prompt-input "test browser use" | Select-String -Pattern "browser-use:browser|Browser Use|failed to load plugin|plugin is not installed"
```

恢复后重启 Codex Desktop。

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

### 3. 推荐：固定 openai-bundled marketplace 路径

不要长期注册带 Codex 版本号的安装目录，例如：

```text
<Codex安装目录>\app\resources\plugins\openai-bundled
```

Codex 更新后这个目录名通常会变化。这里选择复制到 Codex 用户目录下的 bundled marketplace 工作区：

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

这里使用二进制读写复制，而不是普通 `Copy-Item -Recurse`，是为了避开 WindowsApps 等目录可能带来的特殊文件属性问题。

### 4. 重新注册固定 marketplace

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

### 5. 启用 Browser Use 所需配置

开启 `remote_control`：

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

它仍在用户目录下，不会带 Codex 安装包版本号；同时它更接近 Codex 自己维护 bundled marketplace 的位置，未来更新后更可能被新版内容刷新。

**使用 `.tmp` 有什么风险？**

`.tmp` 可能被 Codex 清理或重建。如果发生这种情况，重新复制 bundled marketplace 并执行 `codex plugin marketplace add` 即可恢复。

**为什么示例版本号会变化？**

这只是示例版本。真实版本以 `.codex-plugin\plugin.json` 中的 `version` 为准。Codex cache 使用 `<marketplace>\<plugin>\<version>` 结构，所以目录名必须匹配 manifest。

## English

This guide fixes cases where Codex Desktop's bundled `Browser Use` plugin disappears after an update, appears in the plugin UI but fails to install, or cannot be loaded by `codex debug prompt-input`.

The recommended fix is to mirror the `openai-bundled` marketplace into Codex's bundled marketplace workspace under the user profile and register that path. This avoids breakage when Codex updates and the versioned installation directory changes.

If the mirrored marketplace still exists but Browser Use breaks again, check the plugin cache and config first. A common failure mode is `%USERPROFILE%\.codex\plugins\cache\openai-bundled\browser-use` being removed, or `browser-use@openai-bundled` / `remote_control` disappearing from `config.toml`.

### When to use this

- You use Codex Desktop on Windows.
- Your local Codex installation contains `openai-bundled\plugins\browser-use`.
- `Browser Use` disappeared after a Codex update.
- The plugin UI shows `Browser Use`, but installation fails.
- Debug logs mention `plugin is not installed`.
- `codex debug prompt-input` no longer lists `browser-use:browser`.

### Quick recovery: marketplace exists but Browser Use broke again

If this path exists:

```text
%USERPROFILE%\.codex\.tmp\bundled-marketplaces\openai-bundled\plugins\browser-use
```

rebuild the cache and config using the same recovery script from the Chinese section. The important parts are:

- read `version` from `.codex-plugin\plugin.json`
- copy `plugins\browser-use` into `%USERPROFILE%\.codex\plugins\cache\openai-bundled\browser-use\<version>`
- keep `[plugins."browser-use@openai-bundled"] enabled = true`
- keep `[features] remote_control = true`

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

### 3. Recommended: pin openai-bundled to the bundled marketplace workspace

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

### 4. Re-register the stable marketplace

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

### 5. Enable Browser Use settings

Enable `remote_control`:

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

`.tmp` may be cleaned or rebuilt by Codex. If that happens, copy the bundled marketplace again and rerun `codex plugin marketplace add`.

**Why does the sample version change?**

That is only a sample value. Use the version declared by the plugin manifest. Codex stores cache entries as `<marketplace>\<plugin>\<version>`, so the cache directory must match the manifest.

## HTML version

A standalone HTML version of this guide is included here:

[browser-use-plugin-tutorial.html](./browser-use-plugin-tutorial.html)
