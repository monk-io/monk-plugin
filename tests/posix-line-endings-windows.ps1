param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$ShellFiles = @(git -C $RepoRoot ls-files -- "*.sh")

if ($LASTEXITCODE -ne 0 -or $ShellFiles.Count -eq 0) {
  throw "Could not enumerate tracked POSIX shell files"
}

foreach ($RelativePath in $ShellFiles) {
  $Attribute = git -C $RepoRoot check-attr eol -- $RelativePath
  if ($LASTEXITCODE -ne 0 -or $Attribute -notmatch ': eol: lf$') {
    throw "Missing eol=lf attribute for $RelativePath"
  }

  $Path = Join-Path $RepoRoot ($RelativePath -replace '/', '\')
  $Bytes = [IO.File]::ReadAllBytes($Path)
  for ($Index = 0; $Index -lt $Bytes.Length - 1; $Index++) {
    if ($Bytes[$Index] -eq 13 -and $Bytes[$Index + 1] -eq 10) {
      throw "POSIX shell file contains CRLF: $RelativePath"
    }
  }
}

Write-Host "POSIX shell line-ending tests passed for $($ShellFiles.Count) files."
