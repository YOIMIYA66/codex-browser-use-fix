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

  [pscustomobject]@{
    Plugin = $pluginName
    PackageVersion = $packageVersion
    RuntimeVersion = $runtimeVersion
    Match = $null -ne $packageVersion -and $packageVersion -eq $runtimeVersion
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
  ($rows | Where-Object { -not $_.Match }).Count -eq 0

if (!$healthy) {
  Write-Warning "Bundled marketplace health check failed. Fully restart Codex Desktop, then rerun this script before using manual copy recovery."
  exit 1
}

if (!$managedForCurrentApp) {
  Write-Warning "Plugin manifests match, but the active source is not the current AppX-specific runtime directory. Keep it only as a compatibility fallback."
}

Write-Output "Bundled marketplace health check passed."
