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

    .PARAMETER Source
        Require the value to come from exactly this source - 'EnvironmentVariable', 'Vault', or
        'File' - instead of walking the normal fallback chain. Throws if that source doesn't have
        it, even if another source would. Use this for a sensitive scheduled job that must not
        silently pick up an ambient environment-variable override, or that must fail loudly rather
        than fall back to the weaker DPAPI file if the vault is unreachable.

    .EXAMPLE
        $key = Get-NSPSecret -Name 'CW.Control.ApiKey' -AsPlainText
        $headers.Add('CTRLAuthHeader', $key)

    .EXAMPLE
        $cred = [pscredential]::new('api', (Get-NSPSecret -Name 'Some.Token'))

    .EXAMPLE
        # scheduled task: require the vault specifically, so a leftover NSP_SECRET_* env var
        # from someone's interactive session can't silently override it.
        Get-NSPSecret -Name 'CW.Control.ApiKey' -Source Vault -AsPlainText
    #>
    [CmdletBinding()]
    [OutputType([System.Security.SecureString], [string])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string]$Vault = $script:NSPVaultName,
        [switch]$AsPlainText,
        [ValidateSet('EnvironmentVariable', 'Vault', 'File')][string]$Source
    )

    $envName = 'NSP_SECRET_' + (($Name -replace '[^A-Za-z0-9]', '_').ToUpperInvariant())

    # --- 1. Environment override -------------------------------------------------
    if (-not $Source -or $Source -eq 'EnvironmentVariable') {
        $envVal = [Environment]::GetEnvironmentVariable($envName)
        if (-not [string]::IsNullOrEmpty($envVal)) {
            Write-Verbose "Get-NSPSecret: '$Name' resolved from env var $envName."
            if ($AsPlainText) { return $envVal }
            return (ConvertTo-SecureString -String $envVal -AsPlainText -Force)
        }
        if ($Source -eq 'EnvironmentVariable') {
            throw "Secret '$Name' not found in environment variable $envName (Source 'EnvironmentVariable' was required explicitly; other sources were not checked)."
        }
    }

    # --- 2. SecretManagement vault --------------------------------------------------
    if (-not $Source -or $Source -eq 'Vault') {
        if (-not (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretManagement')) {
            if ($Source -eq 'Vault') {
                throw "Secret '$Name' not found: SecretManagement is not installed (Source 'Vault' was required explicitly)."
            }
        } else {
            try { Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop } catch {
                Write-Verbose "Get-NSPSecret: SecretManagement present but failed to import ($_)."
            }
            $vaultPresent = $false
            try   { $vaultPresent = [bool](Get-SecretVault -Name $Vault -ErrorAction SilentlyContinue) }
            catch { $vaultPresent = $false }

            if (-not $vaultPresent -and $Source -eq 'Vault') {
                throw "Secret '$Name' not found: vault '$Vault' is not registered (Source 'Vault' was required explicitly). Run Initialize-NSPSecretStore."
            }

            if ($vaultPresent -and (Get-SecretInfo -Name $Name -Vault $Vault -ErrorAction SilentlyContinue)) {
                Write-Verbose "Get-NSPSecret: '$Name' resolved from vault '$Vault'."
                $secure = Get-Secret -Name $Name -Vault $Vault -ErrorAction Stop
                if ($secure -is [string]) { $secure = ConvertTo-SecureString -String $secure -AsPlainText -Force }
                if ($AsPlainText) { return (ConvertFrom-NSPSecureString -SecureString $secure) }
                return $secure
            }

            if ($vaultPresent -and $Source -eq 'Vault') {
                throw "Secret '$Name' not found in vault '$Vault' (Source 'Vault' was required explicitly). It may be locked - see Test-NSPSecretStore / Test-NSPSecret."
            }
        }
    }

    # --- 3. DPAPI fallback file -----------------------------------------------------
    if (-not $Source -or $Source -eq 'File') {
        $path = Get-NSPSecretFallbackPath -Name $Name
        if (Test-Path -LiteralPath $path) {
            Write-Verbose "Get-NSPSecret: '$Name' resolved from DPAPI file $path."
            $secure = Get-Content -LiteralPath $path -Raw | ConvertTo-SecureString
            if ($AsPlainText) { return (ConvertFrom-NSPSecureString -SecureString $secure) }
            return $secure
        }
        if ($Source -eq 'File') {
            throw "Secret '$Name' not found: no DPAPI fallback file at $path (Source 'File' was required explicitly)."
        }
    }

    throw ("Secret '{0}' not found. Store it with:  Set-NSPSecret -Name '{0}'   " -f $Name) +
          ("(or set env var {0}). See NSP-Bootstrap\SECRETS.md." -f $envName)
}
