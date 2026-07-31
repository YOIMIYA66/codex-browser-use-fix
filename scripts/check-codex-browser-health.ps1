[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Get-PluginVersion {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$PluginName
  )

  $manifest = Join-Path $Root "plugins\$PluginName\.codex-plugin\plugin.json"
  if (!(Test-Path -LiteralPath $manifest)) {
    return $null
  }

  $plugin = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
  return [string]$plugin.version
}

function Test-Encrypted {
  param([Parameter(Mandatory = $true)][string]$Path)

  $attributes = [System.IO.File]::GetAttributes($Path)
  return ($attributes -band [System.IO.FileAttributes]::Encrypted) -ne 0
}

$codex = Get-Command codex -ErrorAction SilentlyContinue
if ($null -eq $codex) {
  throw "Codex CLI was not found on PATH."
}

$desktop = Get-AppxPackage -Name OpenAI.Codex |
  Sort-Object Version -Descending |
  Select-Object -First 1

if ($null -eq $desktop) {
  throw "OpenAI.Codex AppX package was not found."
}

$packageMarketplace = Join-Path $desktop.InstallLocation "app\resources\plugins\openai-bundled"
$packageManifest = Join-Path $packageMarketplace ".agents\plugins\marketplace.json"
if (!(Test-Path -LiteralPath $packageManifest)) {
  throw "Bundled marketplace is missing from the Desktop package: $packageManifest"
}

$marketplaceOutput = @(& codex plugin marketplace list 2>&1)
if ($LASTEXITCODE -ne 0) {
  throw "Unable to list Codex marketplaces.`n$($marketplaceOutput -join [Environment]::NewLine)"
}

$pluginOutput = @(& codex plugin list --json 2>&1)
if ($LASTEXITCODE -ne 0) {
  throw "Unable to list installed Codex plugins.`n$($pluginOutput -join [Environment]::NewLine)"
}

try {
  $pluginState = ($pluginOutput -join [Environment]::NewLine) | ConvertFrom-Json
} catch {
  throw "Unable to parse 'codex plugin list --json': $($_.Exception.Message)"
}

$installedByName = @{}
foreach ($installedPlugin in @($pluginState.installed)) {
  if ($null -ne $installedPlugin.name) {
    $installedByName[[string]$installedPlugin.name] = $installedPlugin
  }
}

$marketplaceLine = $marketplaceOutput |
  Where-Object { $_ -match '^openai-bundled\s+' } |
  Select-Object -First 1

$runtimeMarketplace = if ($null -eq $marketplaceLine) {
  $null
} else {
  ([string]$marketplaceLine -replace '^openai-bundled\s+', '').Trim()
}

$expectedRuntimeName = "openai-bundled-appx-$($desktop.Version)"
$runtimeExists = $null -ne $runtimeMarketplace -and (Test-Path -LiteralPath $runtimeMarketplace)
$runtimeEncrypted = if ($runtimeExists) { Test-Encrypted -Path $runtimeMarketplace } else { $null }
$managedForCurrentApp = $runtimeExists -and
  ([System.IO.Path]::GetFileName($runtimeMarketplace.TrimEnd('\')) -eq $expectedRuntimeName)

$rows = foreach ($pluginName in @('browser', 'chrome', 'computer-use')) {
  $packageVersion = Get-PluginVersion -Root $packageMarketplace -PluginName $pluginName
  $runtimeVersion = if ($runtimeExists) {
    Get-PluginVersion -Root $runtimeMarketplace -PluginName $pluginName
  } else {
    $null
  }

  $installedPlugin = $installedByName[$pluginName]
  $installedVersion = if ($null -ne $installedPlugin) {
    [string]$installedPlugin.version
  } else {
    $null
  }

  [pscustomobject]@{
    Plugin = $pluginName
    PackageVersion = $packageVersion
    RuntimeVersion = $runtimeVersion
    RuntimeMatch = $null -ne $packageVersion -and $packageVersion -eq $runtimeVersion
    InstalledVersion = $installedVersion
    InstalledMatch = if ($null -eq $installedPlugin) {
      $null
    } else {
      $null -ne $packageVersion -and $packageVersion -eq $installedVersion
    }
  }
}

$cliVersion = (& codex --version 2>&1 | Select-Object -First 1)

Write-Output "Codex browser environment"
Write-Output "  Desktop AppX:        $($desktop.Version)"
Write-Output "  Global CLI:          $cliVersion"
Write-Output "  Package marketplace: $packageMarketplace"
Write-Output "  Runtime marketplace: $($runtimeMarketplace ?? '<not registered>')"
Write-Output "  Expected runtime:    $expectedRuntimeName"
Write-Output "  Current AppX managed: $managedForCurrentApp"
Write-Output "  Runtime encrypted:   $($runtimeEncrypted ?? '<not available>')"
Write-Output ""
$rows | Format-Table -AutoSize

$healthy = $runtimeExists -and
  -not $runtimeEncrypted -and
  ($rows | Where-Object { -not $_.RuntimeMatch }).Count -eq 0 -and
  ($rows | Where-Object { $null -ne $_.InstalledMatch -and -not $_.InstalledMatch }).Count -eq 0

if (!$healthy) {
  Write-Warning "Bundled marketplace or installed plugin versions are out of sync. Review the mismatched columns, fully restart Codex Desktop, and rerun this script before using manual recovery."
  exit 1
}

if (!$managedForCurrentApp) {
  Write-Warning "Plugin manifests match, but the active source is not the current AppX-specific runtime directory. Keep it only as a compatibility fallback."
}

Write-Output "Bundled marketplace health check passed."
