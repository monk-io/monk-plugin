param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$PluginRoots = @(
  $RepoRoot,
  (Join-Path $RepoRoot "plugins\monk")
)

foreach ($PluginRoot in $PluginRoots) {
  $ManifestPath = Join-Path $PluginRoot ".codex-plugin\plugin.json"
  $Manifest = Get-Content -Raw $ManifestPath | ConvertFrom-Json
  $HooksPath = Join-Path $PluginRoot $Manifest.hooks

  if (-not (Test-Path -LiteralPath $HooksPath -PathType Leaf)) {
    throw "Codex hook file does not exist: $HooksPath"
  }

  $Config = Get-Content -Raw $HooksPath | ConvertFrom-Json
  if (-not $Config.hooks.SessionStart) {
    throw "Codex SessionStart hook is missing from $HooksPath"
  }

  $PreToolUse = @($Config.hooks.PreToolUse)
  $BashGuards = @($PreToolUse | Where-Object { $_.matcher -eq "Bash" })
  if ($BashGuards.Count -ne 1) {
    throw "Expected exactly one Codex PreToolUse Bash guard in $HooksPath"
  }

  $Guard = @($BashGuards[0].hooks)
  if ($Guard.Count -ne 1) {
    throw "Expected exactly one command for the Codex PreToolUse Bash guard in $HooksPath"
  }

  foreach ($Property in @("command", "commandWindows")) {
    $Command = $Guard[0].$Property
    if ($Command -notmatch 'block-monk\.(sh|ps1)') {
      throw "Codex $Property does not reference block-monk in $HooksPath"
    }

    $RelativePath = [regex]::Match($Command, '\$\{PLUGIN_ROOT\}/([^" ]*block-monk\.(?:sh|ps1))').Groups[1].Value
    if (-not $RelativePath) {
      throw "Could not resolve Codex $Property in $HooksPath"
    }

    $ResolvedPath = Join-Path $PluginRoot ($RelativePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $ResolvedPath -PathType Leaf)) {
      throw "Codex $Property references a missing file: $ResolvedPath"
    }
  }
}

$RootConfig = (Get-Content -Raw (Join-Path $RepoRoot "hooks\codex-hooks.json")) -replace "`r`n", "`n"
$PackagedConfig = (Get-Content -Raw (Join-Path $RepoRoot "plugins\monk\hooks\codex-hooks.json")) -replace "`r`n", "`n"
if ($RootConfig -cne $PackagedConfig) {
  throw "Root and packaged Codex hook configurations differ"
}

foreach ($HookName in @("block-monk.ps1", "block-monk.sh")) {
  $RootHook = (Get-Content -Raw (Join-Path $RepoRoot "hooks\$HookName")) -replace "`r`n", "`n"
  $PackagedHook = (Get-Content -Raw (Join-Path $RepoRoot "plugins\monk\hooks\$HookName")) -replace "`r`n", "`n"
  if ($RootHook -cne $PackagedHook) {
    throw "Root and packaged $HookName files differ"
  }
}

Write-Host "Codex hook registration tests passed."
