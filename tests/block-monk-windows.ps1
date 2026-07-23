param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$WindowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$RootHook = Join-Path $RepoRoot "hooks\block-monk.ps1"
$AntigravityHook = Join-Path $RepoRoot ".antigravity-plugin\hooks\block-monk.ps1"
$MissingAgent = Join-Path $env:TEMP "missing-monk-agent-$PID.exe"
$PreviousAgentPath = $env:MONK_AGENT_PATH
$PreviousPath = $env:Path

$Cases = @(
  @{ Name = "direct"; Command = "monk deploy"; Denied = $true },
  @{ Name = "newline"; Command = "echo ok`nmonk deploy"; Denied = $true },
  @{ Name = "crlf"; Command = "echo ok`r`nmonk deploy"; Denied = $true },
  @{ Name = "brace"; Command = "{ monk deploy; }"; Denied = $true },
  @{ Name = "newline-sudo"; Command = "echo ok`nsudo monk deploy"; Denied = $true },
  @{ Name = "similar-command"; Command = "monkey deploy"; Denied = $false },
  @{ Name = "argument"; Command = "grep monk README.md"; Denied = $false }
)

function Assert-HookCases {
  param(
    [string]$Hook,
    [ValidateSet("claude", "antigravity")]
    [string]$Format
  )

  foreach ($Case in $Cases) {
    if ($Format -eq "claude") {
      $Payload = @{ tool_input = @{ command = $Case.Command } } | ConvertTo-Json -Compress
      $Output = $Payload | & $WindowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $Hook
      $Denied = [bool]($Output -match '"permissionDecision":"deny"')
    } else {
      $Payload = @{ toolCall = @{ name = "run_command"; args = @{ CommandLine = $Case.Command } } } |
        ConvertTo-Json -Compress -Depth 5
      $Output = $Payload | & $WindowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $Hook
      $Denied = [bool]($Output -match '"decision":"deny"')
    }

    if ($Denied -ne $Case.Denied) {
      throw "$Format hook case '$($Case.Name)' expected denied=$($Case.Denied), got denied=$Denied. Output: $Output"
    }
  }
}

try {
  foreach ($AgentPath in @(
    $MissingAgent,
    (Join-Path $env:SystemRoot "System32\net.exe"),
    (Join-Path $env:SystemRoot "System32\cmd.exe")
  )) {
    $env:MONK_AGENT_PATH = $AgentPath
    Assert-HookCases -Hook $RootHook -Format "claude"
  }

  # Antigravity runs both hook siblings when bash is available. Limit PATH so
  # this test exercises the stock-Windows PowerShell fallback specifically.
  $env:MONK_AGENT_PATH = $MissingAgent
  $env:Path = Split-Path -Parent $WindowsPowerShell
  Assert-HookCases -Hook $AntigravityHook -Format "antigravity"
} finally {
  $env:MONK_AGENT_PATH = $PreviousAgentPath
  $env:Path = $PreviousPath
}

Write-Host "Windows block-monk fallback tests passed."
