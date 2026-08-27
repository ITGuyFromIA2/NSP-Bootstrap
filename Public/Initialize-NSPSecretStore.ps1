function Initialize-NSPSecretStore {
    <#
    .SYNOPSIS
        One-time setup of the local NSP secret vault (SecretManagement + SecretStore).

    .DESCRIPTION
        Installs Microsoft.PowerShell.SecretManagement and Microsoft.PowerShell.SecretStore if
        missing, configures the SecretStore, and registers a vault named 'NSP' as the default.

        Default mode is NO password / NO prompt: the store is unlocked automatically for the
        current Windows user on this machine (DPAPI-equivalent protection). Tradeoff: any process
        running as that same user can read the secrets without a challenge. That is the right
        tradeoff for an interactive tech workstation; for a shared server or an unattended service
        identity use -RequirePassword, or point at Azure Key Vault instead (see SECRETS.md).

    .PARAMETER RequirePassword
        Configure the store to require a password, prompted on first access per session.

    .PARAMETER Scope
        CurrentUser (default) or AllUsers for the module install.

    .EXAMPLE
        Initialize-NSPSecretStore
        # no-password, current-user store - the common case

    .EXAMPLE
        Initialize-NSPSecretStore -RequirePassword
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$RequirePassword,
        [ValidateSet('CurrentUser', 'AllUsers')][string]$Scope = 'CurrentUser'
    )

    Install-NSPModule -Name 'Microsoft.PowerShell.SecretManagement' -MinimumVersion '1.1.2' -Scope $Scope
    Install-NSPModule -Name 'Microsoft.PowerShell.SecretStore'      -MinimumVersion '1.0.6' -Scope $Scope

    Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
    Import-Module Microsoft.PowerShell.SecretStore      -ErrorAction Stop

    $storeConfig = @{
        Confirm = $false
        Scope   = 'CurrentUser'
    }
    if ($RequirePassword) {
        $storeConfig.Authentication = 'Password'
        $storeConfig.Interaction    = 'Prompt'
    } else {
        $storeConfig.Authentication = 'None'
        $storeConfig.Interaction    = 'None'
    }

    if ($PSCmdlet.ShouldProcess('Microsoft.PowerShell.SecretStore', "Set-SecretStoreConfiguration (Authentication=$($storeConfig.Authentication))")) {
        Set-SecretStoreConfiguration @storeConfig -ErrorAction Stop | Out-Null
    }

    if (-not (Get-SecretVault -Name $script:NSPVaultName -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($script:NSPVaultName, 'Register-SecretVault (SecretStore, default)')) {
            Register-SecretVault -Name $script:NSPVaultName -ModuleName 'Microsoft.PowerShell.SecretStore' -DefaultVault -ErrorAction Stop
        }
    } else {
        Write-Verbose "Initialize-NSPSecretStore: vault '$($script:NSPVaultName)' already registered."
    }

    Write-Host "NSP secret vault '$($script:NSPVaultName)' is ready. Store a secret with:  Set-NSPSecret -Name '<Name>'" -ForegroundColor Green
}
