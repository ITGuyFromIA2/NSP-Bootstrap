function Test-NSPSecretStore {
    <#
    .SYNOPSIS
        Reports the local secret-store setup: what's installed, what's registered, and whether
        the vault is actually reachable right now. Diagnostic only - never touches secret values.

    .DESCRIPTION
        Checks, in order:
          - Is Microsoft.PowerShell.SecretManagement installed for this PowerShell edition?
            (Get-NSPSecret's vault lookup silently skips itself if not - this is usually why
            "it works in 5.1 but not pwsh" or vice versa; see NSP-Bootstrap\SECRETS.md.)
          - Is a vault named -Vault registered, and which module backs it (SecretStore,
            Az.KeyVault, etc.)?
          - Is the vault actually reachable right now - Get-SecretInfo against it, discarding the
            result? This is what surfaces a locked or misconfigured SecretStore before a script
            hits it mid-run, rather than failing on the first real Get-NSPSecret call.
          - Is the %LOCALAPPDATA%\NSP\Secrets DPAPI fallback directory present, and how many
            entries does it hold?

    .PARAMETER Vault
        SecretManagement vault name to check. Defaults to 'NSP'.

    .EXAMPLE
        Test-NSPSecretStore

    .EXAMPLE
        Test-NSPSecretStore | Format-List
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Vault = $script:NSPVaultName
    )

    $secretManagementInstalled = [bool](Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretManagement')
    $secretStoreInstalled      = [bool](Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretStore')

    $vaultRegistered = $false
    $vaultModule     = $null
    $vaultReachable  = $false
    $vaultError      = $null

    if ($secretManagementInstalled) {
        try { Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop } catch {
            Write-Verbose "Test-NSPSecretStore: SecretManagement present but failed to import ($_)."
        }
        $vaultInfo = $null
        try { $vaultInfo = Get-SecretVault -Name $Vault -ErrorAction Stop } catch { $vaultInfo = $null }

        if ($vaultInfo) {
            $vaultRegistered = $true
            $vaultModule = $vaultInfo.ModuleName
            try {
                # Discard the result on purpose - this call's only job is to prove the vault
                # will actually answer (unlocked, reachable, correctly configured), not to list
                # anything. An empty vault answering with zero results is still success.
                $null = Get-SecretInfo -Vault $Vault -ErrorAction Stop
                $vaultReachable = $true
            } catch {
                $vaultError = $_.Exception.Message
            }
        }
    }

    $fallbackDir = Join-Path $env:LOCALAPPDATA 'NSP\Secrets'
    $fallbackCount = 0
    if (Test-Path -LiteralPath $fallbackDir) {
        $fallbackCount = @(Get-ChildItem -LiteralPath $fallbackDir -Filter '*.sec' -File -ErrorAction SilentlyContinue).Count
    }

    [pscustomobject]@{
        SecretManagementInstalled = $secretManagementInstalled
        SecretStoreInstalled      = $secretStoreInstalled
        VaultName                 = $Vault
        VaultRegistered           = $vaultRegistered
        VaultBackend              = $vaultModule
        VaultReachable            = $vaultReachable
        VaultError                = $vaultError
        DpapiFallbackDir          = $fallbackDir
        DpapiFallbackCount        = $fallbackCount
    }
}
