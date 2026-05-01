# Codex Browser Use Fix

[中文](#中文) | [English](#english) | [HTML guide](./browser-use-plugin-tutorial.html)

## 中文

这份教程说明如何在 Windows 上启用 Codex Desktop 自带但可能未正常安装的 `Browser Use` 插件。适用于以下情况：

- Codex 插件页能看到 `Browser Use`，但点击安装失败。
- 本地 Codex 安装目录中已经存在 `openai-bundled\plugins\browser-use`。
- `codex debug prompt-input` 报告插件未安装或无法加载。

> 本教程不包含任何个人账号、token 或机器专属路径。请把示例中的 `<Codex安装目录>`、`<版本号>` 等占位符替换为你自己的实际值。

### 1. 确认 browser-use 插件目录存在

先确认本机 Codex Desktop 安装目录下有这个目录：

```text
<Codex安装目录>\app\resources\plugins\openai-bundled\plugins\browser-use
```

PowerShell 检查：

```powershell
$browserUsePath = "<Codex安装目录>\app\resources\plugins\openai-bundled\plugins\browser-use"
Test-Path $browserUsePath
```

返回 `True` 才能继续。

### 2. 读取插件版本号

插件缓存目录必须使用插件元数据里的版本号：

```powershell
Get-Content "$browserUsePath\.codex-plugin\plugin.json"
```

找到类似内容：

```json
{
  "name": "browser-use",
  "version": "0.1.0-alpha1"
}
```

如果你的版本不是 `0.1.0-alpha1`，后续命令里的 `$version` 请改成你自己的版本号。

### 3. 注册 openai-bundled marketplace

注册本地 bundled marketplace：

```powershell
$bundledMarketplace = "<Codex安装目录>\app\resources\plugins\openai-bundled"
codex plugin marketplace add $bundledMarketplace
```

新版 Codex CLI 使用 `codex plugin marketplace add`。部分旧教程里的 `codex marketplace add` 可能已经不适用。

### 4. 开启 remote_control

Browser Use 依赖远程控制能力：

```powershell
codex features enable remote_control
```

检查相关 feature：

```powershell
codex features list | Select-String -Pattern "remote_control|browser_use|in_app_browser|computer_use|plugins"
```

理想情况下，这些项应该是 `true`：

```text
browser_use
computer_use
in_app_browser
plugins
remote_control
```

### 5. 在 config.toml 中启用插件

打开 Codex 配置文件：

```powershell
notepad "$env:USERPROFILE\.codex\config.toml"
```

添加：

```toml
[plugins."browser-use@openai-bundled"]
enabled = true
```

同时确认存在类似配置：

```toml
[marketplaces.openai-bundled]
source_type = "local"
source = "<你的 openai-bundled 路径>"

[features]
remote_control = true
```

### 6. 如果插件页安装失败，手动补齐 cache

正常插件缓存结构是：

```text
%USERPROFILE%\.codex\plugins\cache\openai-bundled\browser-use\<版本号>
```

例如：

```text
%USERPROFILE%\.codex\plugins\cache\openai-bundled\browser-use\0.1.0-alpha1
```

使用下面的 PowerShell 脚本复制插件文件：

```powershell
$src = "<Codex安装目录>\app\resources\plugins\openai-bundled\plugins\browser-use"
$version = "0.1.0-alpha1"
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

这里不使用普通的 `Copy-Item -Recurse`，是为了避开部分 Windows 安装目录上的特殊文件属性导致的复制失败。

### 7. 验证插件是否可加载

检查关键文件：

```powershell
Test-Path "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\browser-use\0.1.0-alpha1\.codex-plugin\plugin.json"
```

返回 `True` 后，检查 Codex 是否能识别插件：

```powershell
codex debug prompt-input "test" | Select-String -Pattern "browser-use|Browser Use"
```

如果输出中出现 `browser-use:browser` 或 `Browser Use`，说明插件已被加载。

### 8. 重启 Codex Desktop

彻底退出并重启 Codex Desktop。重启后，Browser Use 应该可以使用。

如果插件页仍显示未安装，但 `codex debug prompt-input` 已经能看到 `Browser Use`，通常说明功能实际已经加载，不必重复点击安装。

### 中文 FAQ

**为什么版本号是 `0.1.0-alpha1`？**

因为插件自己的 `.codex-plugin\plugin.json` 里写的就是这个版本。Codex 插件缓存目录按 `<marketplace>\<plugin>\<version>` 组织，所以目录名必须和插件元数据一致。

**为什么 UI 能看到插件，但安装失败？**

通常是 marketplace 注册成功了，但插件文件没有成功复制到 `%USERPROFILE%\.codex\plugins\cache`。手动补齐 cache 后即可解决。

## English

This guide explains how to enable the bundled `Browser Use` plugin in Codex Desktop on Windows when the plugin is visible in the UI but installation fails.

It is useful when:

- Codex shows `Browser Use` in the plugin UI, but installation fails.
- Your local Codex installation already contains `openai-bundled\plugins\browser-use`.
- `codex debug prompt-input` reports that the plugin is not installed or cannot be loaded.

> This guide intentionally uses placeholders. Replace `<Codex install directory>`, `<version>`, and similar values with paths from your own machine.

### 1. Confirm that browser-use exists

Check that this directory exists under your Codex Desktop installation:

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

The plugin cache directory must use the version from the plugin manifest:

```powershell
Get-Content "$browserUsePath\.codex-plugin\plugin.json"
```

Look for:

```json
{
  "name": "browser-use",
  "version": "0.1.0-alpha1"
}
```

If your version is different, use that value in later commands.

### 3. Register the openai-bundled marketplace

Register the local bundled marketplace:

```powershell
$bundledMarketplace = "<Codex install directory>\app\resources\plugins\openai-bundled"
codex plugin marketplace add $bundledMarketplace
```

Recent Codex CLI versions use `codex plugin marketplace add`. Older guides may mention `codex marketplace add`, which may no longer apply.

### 4. Enable remote_control

Browser Use depends on the remote-control feature:

```powershell
codex features enable remote_control
```

Check the relevant feature flags:

```powershell
codex features list | Select-String -Pattern "remote_control|browser_use|in_app_browser|computer_use|plugins"
```

Ideally these should be `true`:

```text
browser_use
computer_use
in_app_browser
plugins
remote_control
```

### 5. Enable the plugin in config.toml

Open the Codex config file:

```powershell
notepad "$env:USERPROFILE\.codex\config.toml"
```

Add:

```toml
[plugins."browser-use@openai-bundled"]
enabled = true
```

Also confirm that the config includes something like:

```toml
[marketplaces.openai-bundled]
source_type = "local"
source = "<your openai-bundled path>"

[features]
remote_control = true
```

### 6. If installation fails in the UI, manually populate the cache

The expected plugin cache layout is:

```text
%USERPROFILE%\.codex\plugins\cache\openai-bundled\browser-use\<version>
```

For example:

```text
%USERPROFILE%\.codex\plugins\cache\openai-bundled\browser-use\0.1.0-alpha1
```

Use this PowerShell script to copy the plugin files:

```powershell
$src = "<Codex install directory>\app\resources\plugins\openai-bundled\plugins\browser-use"
$version = "0.1.0-alpha1"
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

This avoids plain `Copy-Item -Recurse` because some Windows install directories can carry special file attributes that make a regular recursive copy fail.

### 7. Verify that Codex can load the plugin

Check the manifest:

```powershell
Test-Path "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\browser-use\0.1.0-alpha1\.codex-plugin\plugin.json"
```

Then check whether Codex can see the plugin:

```powershell
codex debug prompt-input "test" | Select-String -Pattern "browser-use|Browser Use"
```

If the output contains `browser-use:browser` or `Browser Use`, the plugin is loaded.

### 8. Restart Codex Desktop

Quit and restart Codex Desktop completely. Browser Use should now be available.

If the plugin page still says it is not installed but `codex debug prompt-input` can see `Browser Use`, the plugin is usually already loaded and usable.

### English FAQ

**Why is the version `0.1.0-alpha1`?**

Because that is the version declared in the plugin's `.codex-plugin\plugin.json`. Codex stores plugin cache entries as `<marketplace>\<plugin>\<version>`, so the directory name must match the manifest.

**Why can the UI show the plugin while installation fails?**

Usually the marketplace was registered successfully, but the plugin files were not copied into `%USERPROFILE%\.codex\plugins\cache`. Manually populating the cache fixes that state.

## HTML version

A standalone HTML version of this guide is included here:

[browser-use-plugin-tutorial.html](./browser-use-plugin-tutorial.html)
