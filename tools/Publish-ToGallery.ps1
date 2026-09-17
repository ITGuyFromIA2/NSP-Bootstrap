<#
.SYNOPSIS
    Publishes NSP.Bootstrap to the PowerShell Gallery (or another repository).

.DESCRIPTION
    Publish-Module -Path requires the source folder's name to exactly match the module name
    (the manifest's own basename). This repo's working directory is NSP-Bootstrap (hyphen -
    matches the GitHub naming convention every NSP-* repo uses); the module's actual PowerShell
    identity is NSP.Bootstrap (dot - matches standard module naming, e.g. Az.Accounts). That
    mismatch is why a direct `Publish-Module -Path C:\GitRepo\NSP-Bootstrap` fails with
    "no valid module was found with that path."

    This script stages a copy under the correct name in a temp directory and publishes from
    there, rather than renaming the real working directory (which is referenced by path all
    over this repo and its sibling NSP-* repos). Only runtime/user-facing content is staged -
    Tests\, tools\, and dev-only files (.gitignore, PSScriptAnalyzerSettings.psd1, CLAUDE.md)
    are not part of what an Install-Module user gets, so they're not included in the package.

.PARAMETER Repository
    The registered PSRepository to publish to. Defaults to 'PSGallery'. Point this at a local
    test repository (see about_Repositories) to dry-run the staging + publish path without
    touching the real Gallery.

.PARAMETER SecretName
    NSP secret holding the repository API key. Defaults to 'MS.PSGallery.ApiKey'.

.PARAMETER WhatIf
    Stage and validate (Test-ModuleManifest against the staged copy) but skip the actual
    Publish-Module call.

.EXAMPLE
    .\tools\Publish-ToGallery.ps1

.EXAMPLE
    .\tools\Publish-ToGallery.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Repository = 'PSGallery',
    [string]$SecretName = 'MS.PSGallery.ApiKey'
)

$ErrorActionPreference = 'Stop'
$repoRoot   = Split-Path -Parent $PSScriptRoot
$moduleName = 'NSP.Bootstrap'

$manifestPath = Join-Path $repoRoot "$moduleName.psd1"
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath

# What actually ships to Install-Module users - runtime code + user-facing docs, not the dev
# tooling (Tests\, tools\, lint settings, AI-agent instructions) that only matters in this repo.
$publishItems = @(
    "$moduleName.psd1"
    "$moduleName.psm1"
    'Public'
    'Private'
    'README.md'
    'LICENSE'
    'CHANGELOG.md'
    'SECRETS.md'
) | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) }

$stageRoot       = Join-Path ([System.IO.Path]::GetTempPath()) ('NSPBootstrapPublish_' + [guid]::NewGuid().ToString('N'))
$stageModuleDir  = Join-Path $stageRoot $moduleName
# -WhatIf:$false on every staging operation below: this script's own -WhatIf/-Confirm would
# otherwise auto-propagate to New-Item/Copy-Item (they support ShouldProcess too), which
# would silently skip the staging and validation entirely instead of just skipping the real
# publish. Staging into a throwaway temp dir isn't the operation worth previewing - only the
# actual Publish-Module call, gated below, is.
New-Item -ItemType Directory -Path $stageModuleDir -Force -WhatIf:$false | Out-Null

try {
    foreach ($item in $publishItems) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $item) -Destination (Join-Path $stageModuleDir $item) -Recurse -Force -WhatIf:$false
    }
    Write-Host "Staged $moduleName $($manifest.ModuleVersion) at $stageModuleDir" -ForegroundColor DarkGray

    # Fails loudly here, before anything touches the network, if the staged copy is somehow
    # incomplete or the manifest doesn't parse.
    $null = Test-ModuleManifest -Path (Join-Path $stageModuleDir "$moduleName.psd1") -ErrorAction Stop
    Write-Host "Staged manifest OK." -ForegroundColor DarkGray

    if (-not (Get-Module -ListAvailable -Name PowerShellGet | Where-Object Version -ge '2.0')) {
        Write-Warning "PowerShellGet 2.x+ not found - Publish-Module may be the old 1.0.0.1 in-box version. If this fails oddly, 'Install-NSPModule -Name PowerShellGet -MinimumVersion 2.2.5' first."
    }

    if ($PSCmdlet.ShouldProcess("$moduleName $($manifest.ModuleVersion) -> $Repository", 'Publish-Module')) {
        # Only touches the secret store / network on a real (non -WhatIf) run.
        $NSPBootstrapManifest = 'C:\GitRepo\NSP-Bootstrap\NSP.Bootstrap.psd1'
        if (Test-Path $NSPBootstrapManifest) { Import-Module $NSPBootstrapManifest -Force -ErrorAction Stop }
        else { Import-Module NSP.Bootstrap -Force -ErrorAction Stop }
        $apiKey = Get-NSPSecret -Name $SecretName -AsPlainText

        Publish-Module -Path $stageModuleDir -NuGetApiKey $apiKey -Repository $Repository
        Write-Host "Published $moduleName $($manifest.ModuleVersion) to $Repository." -ForegroundColor Green
    }
} finally {
    # Real cleanup even under -WhatIf, for the same reason staging above forces -WhatIf:$false -
    # otherwise every -WhatIf run leaves its temp directory behind.
    Remove-Item -LiteralPath $stageRoot -Recurse -Force -WhatIf:$false -ErrorAction SilentlyContinue
}
