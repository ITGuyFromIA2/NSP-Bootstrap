function Install-NSPModule {
    <#
    .SYNOPSIS
        Ensures one or more PSGallery modules are present (optionally at a minimum version),
        installing for the current user if they are not.

    .DESCRIPTION
        Consolidates the "Set-PSRepository / Find-Module / compare / Install-Module" block that is
        copy-pasted across the NSP scripts. Deliberately conservative:
          - Does NOT permanently mark PSGallery trusted (uses Install-Module -Force to suppress the
            per-call prompt instead).
          - Installs to CurrentUser scope by default (no elevation needed).
          - Forces TLS 1.2 first - Windows PowerShell 5.1 defaults to SSL3/TLS1.0 and the gallery
            refuses those.

    .PARAMETER Name
        One or more module names.

    .PARAMETER MinimumVersion
        If set, a module already present below this version is upgraded.

    .PARAMETER Scope
        CurrentUser (default) or AllUsers (needs elevation).

    .PARAMETER Force
        Reinstall even if a satisfying version is already present.

    .PARAMETER SkipPublisherCheck
        Pass through to Install-Module. Needed when upgrading a module that shipped in-box under a
        Microsoft signature to a gallery build signed by a different publisher - the classic case
        is Pester 3.4.0 (in-box) -> Pester 5/6.

    .EXAMPLE
        Install-NSPModule -Name Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore

    .EXAMPLE
        Install-NSPModule -Name Pester -MinimumVersion 5.5.0 -SkipPublisherCheck
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string[]]$Name,
        [string]$MinimumVersion,
        [ValidateSet('CurrentUser', 'AllUsers')][string]$Scope = 'CurrentUser',
        [switch]$Force,
        [switch]$SkipPublisherCheck
    )

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Verbose "Install-NSPModule: could not set TLS 1.2 ($_) - continuing."
    }

    foreach ($moduleName in $Name) {

        $satisfying = Get-Module -ListAvailable -Name $moduleName |
            Where-Object { -not $MinimumVersion -or $_.Version -ge [version]$MinimumVersion } |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($satisfying -and -not $Force) {
            Write-Verbose "Install-NSPModule: '$moduleName' $($satisfying.Version) already present."
            continue
        }

        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess('NuGet', 'Install-PackageProvider')) {
                Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Scope $Scope -Force | Out-Null
            }
        }

        $installParams = @{
            Name         = $moduleName
            Scope        = $Scope
            Force        = $true
            AllowClobber = $true
            ErrorAction  = 'Stop'
        }
        if ($MinimumVersion)     { $installParams.MinimumVersion     = $MinimumVersion }
        if ($SkipPublisherCheck) { $installParams.SkipPublisherCheck = $true }

        if ($PSCmdlet.ShouldProcess($moduleName, "Install-Module (scope $Scope)")) {
            Write-Verbose "Install-NSPModule: installing '$moduleName'..."
            Install-Module @installParams
        }
    }
}
