[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$DryRun,
  [string]$CodexDataRoot = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex")
)

$ErrorActionPreference = "Stop"

function Get-DesktopBundleHash {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string[]]$RelativePaths
  )

  $builder = [System.Text.StringBuilder]::new()
  foreach ($relativePath in $RelativePaths) {
    $source = Join-Path $Root $relativePath
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) {
      throw "Bundled runtime file is missing: $source"
    }

    $digest = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    [void]$builder.Append($relativePath)
    [void]$builder.Append([char]0)
    [void]$builder.Append($digest)
    [void]$builder.Append([char]0)
  }

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Test-BundleTarget {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string[]]$RequiredFiles,
    [switch]$CompareFileCount
  )

  if (!(Test-Path -LiteralPath $Target -PathType Container)) {
    return $false
  }

  foreach ($relativePath in $RequiredFiles) {
    $sourceFile = Join-Path $Source $relativePath
    $targetFile = Join-Path $Target $relativePath
    if (!(Test-Path -LiteralPath $targetFile -PathType Leaf)) {
      return $false
    }
    if ((Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash) {
      return $false
    }
  }

  if ($CompareFileCount) {
    $sourceCount = @(Get-ChildItem -LiteralPath $Source -Recurse -File -Force).Count
    $targetCount = @(Get-ChildItem -LiteralPath $Target -Recurse -File -Force).Count
    if ($sourceCount -ne $targetCount) {
      return $false
    }
  }

  $encryptedCount = @(
    Get-ChildItem -LiteralPath $Target -Recurse -Force |
      Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::Encrypted) -ne 0 }
  ).Count
  return $encryptedCount -eq 0
}

function Install-BundleTarget {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string[]]$RequiredFiles,
    [switch]$Recursive
  )

  if (Test-BundleTarget -Source $Source -Target $Target -RequiredFiles $RequiredFiles -CompareFileCount:$Recursive) {
    Write-Output "healthy: $Target"
    return
  }

  if (Test-Path -LiteralPath $Target) {
    throw "Runtime target exists but failed validation; refusing to overwrite it: $Target"
  }

  if ($DryRun) {
    Write-Output "would-create: $Target"
    return
  }

  $parent = Split-Path -Parent $Target
  $leaf = Split-Path -Leaf $Target
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  $staging = Join-Path $parent (".staging-{0}-{1}" -f $leaf, [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $staging | Out-Null

  if ($Recursive) {
    & robocopy $Source $staging /E /COPY:DAT /DCOPY:DAT /A-:E /R:1 /W:1 /XJ /NFL /NDL /NJH /NJS /NP
  } else {
    & robocopy $Source $staging @RequiredFiles /COPY:DAT /A-:E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
  }
  $robocopyExitCode = $LASTEXITCODE
  if ($robocopyExitCode -gt 7) {
    throw "robocopy failed with exit code $robocopyExitCode; staging retained at $staging"
  }

  if (!(Test-BundleTarget -Source $Source -Target $staging -RequiredFiles $RequiredFiles -CompareFileCount:$Recursive)) {
    throw "Staged runtime failed validation; staging retained at $staging"
  }

  if ($PSCmdlet.ShouldProcess($Target, "Install validated Codex Desktop runtime")) {
    Move-Item -LiteralPath $staging -Destination $Target
    Write-Output "created: $Target"
  }
}

$desktop = Get-AppxPackage -Name OpenAI.Codex |
  Sort-Object Version -Descending |
  Select-Object -First 1
if ($null -eq $desktop) {
  throw "OpenAI.Codex AppX package was not found."
}

$resources = Join-Path $desktop.InstallLocation "app\resources"
$codexFiles = @(
  'codex.exe',
  'codex-code-mode-host.exe',
  'codex-windows-sandbox-setup.exe',
  'codex-command-runner.exe'
)
$cuaFiles = @('manifest.json', 'bin/node.exe', 'bin/node_repl.exe')
$cuaSource = Join-Path $resources 'cua_node'

$codexHash = (Get-DesktopBundleHash -Root $resources -RelativePaths $codexFiles).Substring(0, 16)
$cuaHash = (Get-DesktopBundleHash -Root $cuaSource -RelativePaths $cuaFiles).Substring(0, 16)
$codexTarget = Join-Path $CodexDataRoot "bin\$codexHash"
$cuaTarget = Join-Path $CodexDataRoot "runtimes\cua_node\$cuaHash"

Write-Output "Codex Desktop runtime recovery"
Write-Output "  Desktop AppX: $($desktop.Version)"
Write-Output "  Resources:    $resources"
Write-Output "  Codex target: $codexTarget"
Write-Output "  CUA target:   $cuaTarget"

Install-BundleTarget -Source $resources -Target $codexTarget -RequiredFiles $codexFiles
Install-BundleTarget -Source $cuaSource -Target $cuaTarget -RequiredFiles $cuaFiles -Recursive

if (!$DryRun) {
  & (Join-Path $codexTarget 'codex.exe') --version
  & (Join-Path $cuaTarget 'bin\node.exe') --version
  & (Join-Path $cuaTarget 'bin\node_repl.exe') --help | Select-Object -First 1
  Write-Output "Runtime recovery completed. Fully quit and restart Codex Desktop so it can reconcile the Chrome native host."
}
