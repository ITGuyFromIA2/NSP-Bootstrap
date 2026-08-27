<#
.SYNOPSIS
    Pre-push check for NSP-Bootstrap: PSScriptAnalyzer, then Pester 5. Exits non-zero if either
    fails. This is the pattern the other NSP repos should copy.

.DESCRIPTION
    Requires PSScriptAnalyzer and Pester >= 5.5. If either is missing it prints the one-liner to
    install them (via this module's own Install-NSPModule) and exits 2 - it does NOT install
    anything silently.

.PARAMETER InstallDeps
    Install missing PSScriptAnalyzer / Pester 5 for the current user, then run.

.EXAMPLE
    .\tools\Test-Repo.ps1

.EXAMPLE
    .\tools\Test-Repo.ps1 -InstallDeps
#>
[CmdletBinding()]
param(
    [switch]$InstallDeps
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'NSP.Bootstrap.psd1') -Force

function Test-Dep {
    param([string]$Name, [version]$Min)
    Get-Module -ListAvailable -Name $Name | Where-Object { $_.Version -ge $Min } | Select-Object -First 1
}

$needAnalyzer = -not (Test-Dep -Name 'PSScriptAnalyzer' -Min ([version]'1.21.0'))
$needPester   = -not (Test-Dep -Name 'Pester'           -Min ([version]'5.5.0'))

if ($needAnalyzer -or $needPester) {
    if ($InstallDeps) {
        if ($needAnalyzer) { Install-NSPModule -Name PSScriptAnalyzer -MinimumVersion 1.21.0 -Verbose }
        if ($needPester)   { Install-NSPModule -Name Pester -MinimumVersion 5.5.0 -Verbose }
    } else {
        Write-Host ""
        Write-Host "Missing test dependencies. Install them with:" -ForegroundColor Yellow
        Write-Host "  Import-Module '$repoRoot\NSP.Bootstrap.psd1'" -ForegroundColor Yellow
        Write-Host "  Install-NSPModule -Name PSScriptAnalyzer,Pester -MinimumVersion 5.5.0" -ForegroundColor Yellow
        Write-Host "or re-run:  .\tools\Test-Repo.ps1 -InstallDeps" -ForegroundColor Yellow
        exit 2
    }
}

Import-Module PSScriptAnalyzer -Force
Import-Module Pester -MinimumVersion 5.5.0 -Force

$failed = $false

Write-Host "`n=== PSScriptAnalyzer ===" -ForegroundColor Cyan
$analysis = Invoke-ScriptAnalyzer -Path $repoRoot -Recurse -Settings (Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1')
if ($analysis) {
    $analysis | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message
    if ($analysis | Where-Object Severity -in 'Error', 'Warning') { $failed = $true }
} else {
    Write-Host "clean" -ForegroundColor Green
}

Write-Host "`n=== Pester ===" -ForegroundColor Cyan
$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path = Join-Path $repoRoot 'Tests'
$pesterConfig.Output.Verbosity = 'Detailed'
$pesterConfig.Run.PassThru = $true
$result = Invoke-Pester -Configuration $pesterConfig
if ($result.FailedCount -gt 0) { $failed = $true }

if ($failed) {
    Write-Host "`nRESULT: FAIL" -ForegroundColor Red
    exit 1
}
Write-Host "`nRESULT: PASS" -ForegroundColor Green
exit 0
