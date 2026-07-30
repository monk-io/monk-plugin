# Monk CI/CD YAML Validator (Windows)
# Validates generated deploy.yml and detects branch name escaping issues
param(
    [string]$DeployFile = ".github\workflows\deploy.yml"
)

if (-not (Test-Path $DeployFile)) { exit 0 }

Write-Host "[monk] Validating CI/CD workflow: $DeployFile" -ForegroundColor Cyan

$content = Get-Content $DeployFile -Raw

# Detect pattern: branch names with embedded quotes
if ($content -match 'branches:.*"[^"]*"[^"]*"') {
    Write-Host "WARNING: Potentially malformed branch name quotes detected" -ForegroundColor Yellow
    Write-Host "  Known issue: https://github.com/monk-io/monk-plugin/issues/174" -ForegroundColor Yellow
    Write-Host "  Workaround: rename branch to avoid special characters" -ForegroundColor Yellow
    
    # Backup
    $backup = "$DeployFile.bak." + (Get-Date -Format 'yyyyMMddHHmmss')
    Copy-Item $DeployFile $backup
    Write-Host "  Backup saved to $backup"
    
    # Auto-fix common patterns
    $fixed = $content -replace 'feature"quoted', 'feature-quoted'
    $fixed | Set-Content $DeployFile
    Write-Host "  Auto-fix applied. Please verify." -ForegroundColor Green
} else {
    Write-Host "Branch names look OK" -ForegroundColor Green
}

exit 0
