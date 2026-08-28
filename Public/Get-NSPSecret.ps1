function Get-NSPSecret {
    <#
    .SYNOPSIS
        Retrieves a stored secret by name. Single call site for every NSP script that needs a
        credential, API key, or token.

    .DESCRIPTION
        Resolution order (first hit wins):

          1. Environment variable  NSP_SECRET_<NAME>  (name upper-cased, non-alphanumerics -> _).
             For CI and one-off overrides. Plaintext by nature - only use where the environment
             itself is the secret store.
          2. SecretManagement vault (default 'NSP'), if the module and vault are present.
          3. DPAPI fallback file  %LOCALAPPDATA%\NSP\Secrets\<name>.sec  (current user + machine).

        If none match, throws with the exact command to fix it.

        Returns a [SecureString] by default. Pass -AsPlainText for a [string] (e.g. to put in an
        HTTP header).

    .PARAMETER Name
        The secret name, e.g. 'CW.Control.ApiKey'.

    .PARAMETER Vault
        SecretManagement vault name. Defaults to 'NSP'.

    .PARAMETER AsPlainText
        Return a plain [string] instead of a [SecureString].

    .EXAMPLE
        $key = Get-NSPSecret -Name 'CW.Control.ApiKey' -AsPlainText
        $headers.Add('CTRLAuthHeader', $key)

    .EXAMPLE
        $cred = [pscredential]::new('api', (Get-NSPSecret -Name 'Some.Token'))
    #>
    [CmdletBinding()]
    [OutputType([System.Security.SecureString], [string])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string]$Vault = $script:NSPVaultName,
        [switch]$AsPlainText
    )

    # --- 1. Environment override -------------------------------------------------
    $envName = 'NSP_SECRET_' + (($Name -replace '[^A-Za-z0-9]', '_').ToUpperInvariant())
    $envVal  = [Environment]::GetEnvironmentVariable($envName)
    if (-not [string]::IsNullOrEmpty($envVal)) {
        Write-Verbose "Get-NSPSecret: '$Name' resolved from env var $envName."
        if ($AsPlainText) { return $envVal }
        return (ConvertTo-SecureString -String $envVal -AsPlainText -Force)
    }

    # --- 2. SecretManagement vault --------------------------------------------------
    if (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretManagement') {
        try { Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop } catch {
            Write-Verbose "Get-NSPSecret: SecretManagement present but failed to import ($_)."
        }
        $vaultPresent = $false
        try   { $vaultPresent = [bool](Get-SecretVault -Name $Vault -ErrorAction SilentlyContinue) }
        catch { $vaultPresent = $false }

        if ($vaultPresent -and (Get-SecretInfo -Name $Name -Vault $Vault -ErrorAction SilentlyContinue)) {
            Write-Verbose "Get-NSPSecret: '$Name' resolved from vault '$Vault'."
            $secure = Get-Secret -Name $Name -Vault $Vault -ErrorAction Stop
            if ($secure -is [string]) { $secure = ConvertTo-SecureString -String $secure -AsPlainText -Force }
            if ($AsPlainText) { return (ConvertFrom-NSPSecureString -SecureString $secure) }
            return $secure
        }
    }

    # --- 3. DPAPI fallback file -----------------------------------------------------
    $path = Get-NSPSecretFallbackPath -Name $Name
    if (Test-Path -LiteralPath $path) {
        Write-Verbose "Get-NSPSecret: '$Name' resolved from DPAPI file $path."
        $secure = Get-Content -LiteralPath $path -Raw | ConvertTo-SecureString
        if ($AsPlainText) { return (ConvertFrom-NSPSecureString -SecureString $secure) }
        return $secure
    }

    throw ("Secret '{0}' not found. Store it with:  Set-NSPSecret -Name '{0}'   " -f $Name) +
          ("(or set env var {0}). See NSP-Bootstrap\SECRETS.md." -f $envName)
}
