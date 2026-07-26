[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$CodexDataRoot = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex")
)

$ErrorActionPreference = "Stop"
$isWhatIf = [bool]$WhatIfPreference
# Keep WhatIf from suppressing read-only work inside AppX and hashing cmdlets.
$WhatIfPreference = $false

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
    [switch]$CompareAllFiles
  )

  if (!(Test-Path -LiteralPath $Target -PathType Container)) {
    return $false
  }

  foreach ($relativePath in $RequiredFiles) {
    $sourceFile = Join-Path $Source $relativePath
    $targetFile = Join-Path $Target $relativePath
    if (!(Test-Path -LiteralPath $sourceFile -PathType Leaf) -or
        !(Test-Path -LiteralPath $targetFile -PathType Leaf)) {
      return $false
    }
  }

  if ($CompareAllFiles) {
    $sourceInventory = Get-RelativeFileInventory -Root $Source
    $targetInventory = Get-RelativeFileInventory -Root $Target
    if ($sourceInventory.Count -ne $targetInventory.Count) {
      return $false
    }

    foreach ($relativePath in $sourceInventory.Hashes.Keys) {
      if (!$targetInventory.Hashes.ContainsKey($relativePath) -or
          $sourceInventory.Hashes[$relativePath] -ne $targetInventory.Hashes[$relativePath]) {
        return $false
      }
    }
  } else {
    foreach ($relativePath in $RequiredFiles) {
      $sourceFile = Join-Path $Source $relativePath
      $targetFile = Join-Path $Target $relativePath
      if ((Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash -ne
          (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash) {
        return $false
      }
    }
  }

  $encryptedCount = @(
    Get-ChildItem -LiteralPath $Target -Recurse -Force |
      Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::Encrypted) -ne 0 }
  ).Count
  return $encryptedCount -eq 0
}

function Get-RelativeFileInventory {
  param(
    [Parameter(Mandatory = $true)][string]$Root
  )

  $rootPath = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd('\')
  $rootPrefix = "$rootPath\"
  $hashes = [System.Collections.Generic.Dictionary[string, string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )

  foreach ($file in Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force) {
    if (!$file.FullName.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Runtime file escaped its source root: $($file.FullName)"
    }

    $relativePath = $file.FullName.Substring($rootPrefix.Length)
    if ($hashes.ContainsKey($relativePath)) {
      throw "Duplicate runtime path found: $relativePath"
    }

    $hashes.Add(
      $relativePath,
      (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    )
  }

  [pscustomobject]@{
    Count = $hashes.Count
    Hashes = $hashes
  }
}

function Install-BundleTarget {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string[]]$RequiredFiles,
    [switch]$Recursive
  )

  $installWhatIf = [bool]$WhatIfPreference
  $WhatIfPreference = $false

  if (Test-BundleTarget -Source $Source -Target $Target -RequiredFiles $RequiredFiles -CompareAllFiles:$Recursive) {
    Write-Output "healthy: $Target"
    return
  }

  if (Test-Path -LiteralPath $Target) {
    throw "Runtime target exists but failed validation; refusing to overwrite it: $Target"
  }

  $WhatIfPreference = $installWhatIf
  if (!$PSCmdlet.ShouldProcess($Target, "Install validated Codex Desktop runtime")) {
    return
  }
  $WhatIfPreference = $false

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

  if (!(Test-BundleTarget -Source $Source -Target $staging -RequiredFiles $RequiredFiles -CompareAllFiles:$Recursive)) {
    throw "Staged runtime failed validation; staging retained at $staging"
  }

  if (Test-Path -LiteralPath $Target) {
    throw "Runtime target appeared during staging; refusing to replace it. Staging retained at $staging"
  }

  try {
    [System.IO.Directory]::Move($staging, $Target)
  } catch {
    throw "Failed to install the validated runtime; staging retained at $staging. $($_.Exception.Message)"
  }
  Write-Output "created: $Target"
}

function Invoke-RuntimeSmokeTest {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [int]$OutputLines = [int]::MaxValue
  )

  $output = @(& $Executable @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  if ($null -eq $exitCode -or $exitCode -ne 0) {
    $firstLine = $output | Select-Object -First 1
    throw "$Name smoke test failed with exit code $exitCode. First output: $firstLine"
  }

  $output | Select-Object -First $OutputLines
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
$cuaSource = Join-Path $resources 'cua_node'
$cuaManifestPath = Join-Path $cuaSource 'manifest.json'
if (!(Test-Path -LiteralPath $cuaManifestPath -PathType Leaf)) {
  throw "CUA runtime manifest is missing: $cuaManifestPath"
}

$cuaManifest = Get-Content -LiteralPath $cuaManifestPath -Raw | ConvertFrom-Json
if ($cuaManifest.platform -ne 'windows' -or
    [string]::IsNullOrWhiteSpace([string]$cuaManifest.node_path) -or
    [string]::IsNullOrWhiteSpace([string]$cuaManifest.node_repl_path)) {
  throw "CUA runtime manifest does not match the supported Windows schema: $cuaManifestPath"
}
$cuaFiles = @('manifest.json', [string]$cuaManifest.node_path, [string]$cuaManifest.node_repl_path)

$codexHash = (Get-DesktopBundleHash -Root $resources -RelativePaths $codexFiles).Substring(0, 16)
$cuaHash = (Get-DesktopBundleHash -Root $cuaSource -RelativePaths $cuaFiles).Substring(0, 16)
$codexTarget = Join-Path $CodexDataRoot "bin\$codexHash"
$cuaTarget = Join-Path $CodexDataRoot "runtimes\cua_node\$cuaHash"

Write-Output "Codex Desktop runtime recovery"
Write-Output "  Desktop AppX: $($desktop.Version)"
Write-Output "  Resources:    $resources"
Write-Output "  Codex target: $codexTarget"
Write-Output "  CUA target:   $cuaTarget"

Install-BundleTarget -Source $resources -Target $codexTarget -RequiredFiles $codexFiles -WhatIf:$isWhatIf
Install-BundleTarget -Source $cuaSource -Target $cuaTarget -RequiredFiles $cuaFiles -Recursive -WhatIf:$isWhatIf

if (!$isWhatIf) {
  Invoke-RuntimeSmokeTest -Name 'codex.exe' -Executable (Join-Path $codexTarget 'codex.exe') -Arguments @('--version')
  Invoke-RuntimeSmokeTest -Name 'node.exe' -Executable (Join-Path $cuaTarget $cuaManifest.node_path) -Arguments @('--version')
  Invoke-RuntimeSmokeTest -Name 'node_repl.exe' -Executable (Join-Path $cuaTarget $cuaManifest.node_repl_path) -Arguments @('--help') -OutputLines 1
  Write-Output "Runtime recovery completed. Fully quit and restart Codex Desktop so it can reconcile the Chrome native host."
}
