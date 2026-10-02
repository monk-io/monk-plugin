param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$WindowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$RootHook = Join-Path $RepoRoot "hooks\block-monk.ps1"
$PluginHook = Join-Path $RepoRoot "plugins\monk\hooks\block-monk.ps1"
$AntigravityHook = Join-Path $RepoRoot ".antigravity-plugin\hooks\block-monk.ps1"
$MissingAgent = Join-Path $env:TEMP "missing-monk-agent-$PID.exe"
$PreviousAgentPath = $env:MONK_AGENT_PATH

$Cases = @(
  @{ Name = "direct"; Command = "monk deploy"; Denied = $true },
  @{ Name = "newline"; Command = "echo ok`nmonk deploy"; Denied = $true },
  @{ Name = "crlf"; Command = "echo ok`r`nmonk deploy"; Denied = $true },
  @{ Name = "brace"; Command = "{ monk deploy; }"; Denied = $true },
  @{ Name = "newline-sudo"; Command = "echo ok`nsudo monk deploy"; Denied = $true },
  @{ Name = "similar-command"; Command = "monkey deploy"; Denied = $false },
  @{ Name = "argument"; Command = "grep monk README.md"; Denied = $false },
  # ENG-412: quoted/escaped monk no longer defeats detection.
  @{ Name = "quoted"; Command = '"monk" deploy'; Denied = $true },
  @{ Name = "escaped"; Command = 'm\onk deploy'; Denied = $true },
  # ENG-444: wrapper-prefixed and path-qualified monk invocations.
  @{ Name = "wrapper-command"; Command = "command monk deploy"; Denied = $true },
  @{ Name = "wrapper-env"; Command = "env monk deploy"; Denied = $true },
  @{ Name = "wrapper-powershell"; Command = "powershell.exe -Command monk deploy"; Denied = $true },
  @{ Name = "path-qualified"; Command = "/usr/local/bin/monk deploy"; Denied = $true },
  # ENG-448: the monkd daemon binary is blocked too, but monkdb (a different
  # program) is not — the trailing boundary still requires whitespace/EOL.
  @{ Name = "monkd"; Command = "monkd status"; Denied = $true },
  @{ Name = "monkdb-lookalike"; Command = "monkdb migrate"; Denied = $false },
  # A quoted or escaped `|` is a grep alternation, not a pipeline; a real
  # pipe, or one inside a re-parsed `sh -c` string, still counts.
  @{ Name = "quoted-bre-alternation"; Command = 'grep -n "a\|monk" f'; Denied = $false },
  @{ Name = "quoted-ere-alternation"; Command = 'grep -nE ''a|monk'' f'; Denied = $false },
  @{ Name = "escaped-pipe"; Command = 'grep a\|monk f'; Denied = $false },
  @{ Name = "real-pipe"; Command = 'grep "a|b" f | monk deploy'; Denied = $true },
  @{ Name = "sh-c-pipe"; Command = 'sh -c "echo x | monk deploy"'; Denied = $true }
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
      $Output = $Payload | & $WindowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $Hook -Format antigravity
      $Denied = [bool]($Output -match '"decision":"deny"')
    }

    if ($Denied -ne $Case.Denied) {
      throw "$Format hook case '$($Case.Name)' expected denied=$($Case.Denied), got denied=$Denied. Output: $Output"
    }
  }
}

try {
  # Exercise the missing-binary fallback plus a nonzero-exit helper (net.exe
  # with no args fails) and a successful-but-malformed-output helper
  # (cmd.exe /c echo prints text that isn't the expected decision JSON) — both
  # must fall through to the native parser instead of silently allowing.
  foreach ($AgentPath in @(
    $MissingAgent,
    (Join-Path $env:SystemRoot "System32\net.exe"),
    (Join-Path $env:SystemRoot "System32\cmd.exe")
  )) {
    $env:MONK_AGENT_PATH = $AgentPath
    Assert-HookCases -Hook $RootHook -Format "claude"
    Assert-HookCases -Hook $PluginHook -Format "claude"
    # The Antigravity bundle carries the same shared script, run with -Format antigravity.
    Assert-HookCases -Hook $AntigravityHook -Format "antigravity"
  }
} finally {
  $env:MONK_AGENT_PATH = $PreviousAgentPath
}

Write-Host "Windows block-monk fallback tests passed."
