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

        Only touches the store's Authentication mode on first-time setup (vault not yet
        registered) or when -RequirePassword is passed explicitly. A bare rerun against an
        already-registered vault - e.g. to pick up a module update - leaves the existing
        Authentication mode alone, so it can't silently downgrade a password-protected store back
        to no-password. To deliberately change modes on an existing store, pass -RequirePassword
        (or run Set-SecretStoreConfiguration directly to remove it).

    .PARAMETER RequirePassword
        Configure the store to require a password, prompted on first access per session. Also
        forces the Authentication mode to be (re)applied even if the vault is already registered.

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

    # Decide up front whether this is first-time setup - that's what governs whether we're
    # allowed to touch the store's Authentication mode below.
    $vaultAlreadyRegistered = [bool](Get-SecretVault -Name $script:NSPVaultName -ErrorAction SilentlyContinue)

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

    # First-time setup always applies the requested mode. On a rerun against an already-registered
    # vault, only apply it if -RequirePassword was passed explicitly - otherwise a plain rerun
    # (e.g. after a module update) would silently reset an existing password-protected store back
    # to no-password, since $RequirePassword defaults to $false whether or not the caller cared.
    if (-not $vaultAlreadyRegistered -or $PSBoundParameters.ContainsKey('RequirePassword')) {
        if ($PSCmdlet.ShouldProcess('Microsoft.PowerShell.SecretStore', "Set-SecretStoreConfiguration (Authentication=$($storeConfig.Authentication))")) {
            Set-SecretStoreConfiguration @storeConfig -ErrorAction Stop | Out-Null
        }
    } else {
        Write-Verbose "Initialize-NSPSecretStore: vault already registered and -RequirePassword not specified - leaving the existing SecretStore authentication mode as-is."
    }

    if (-not $vaultAlreadyRegistered) {
        if ($PSCmdlet.ShouldProcess($script:NSPVaultName, 'Register-SecretVault (SecretStore, default)')) {
            Register-SecretVault -Name $script:NSPVaultName -ModuleName 'Microsoft.PowerShell.SecretStore' -DefaultVault -ErrorAction Stop
        }
    } else {
        Write-Verbose "Initialize-NSPSecretStore: vault '$($script:NSPVaultName)' already registered."
    }

    Write-Host "NSP secret vault '$($script:NSPVaultName)' is ready. Store a secret with:  Set-NSPSecret -Name '<Name>'" -ForegroundColor Green
}
