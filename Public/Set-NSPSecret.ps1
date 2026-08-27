function Set-NSPSecret {
    <#
    .SYNOPSIS
        Stores (or replaces) a named secret.

    .DESCRIPTION
        Writes to the SecretManagement vault (default 'NSP') unless -Scope File is given, which
        writes the DPAPI fallback file instead.

        If -Secret is omitted the value is read with Read-Host -AsSecureString, so it never lands
        in shell history, a script file, or a transcript. Prefer that.

    .PARAMETER Name
        Secret name, e.g. 'CW.Control.ApiKey'.

    .PARAMETER Secret
        The value: a [string], a [SecureString], or omitted (prompt). A plain string is accepted
        for scripted migration but is the least safe path.

    .PARAMETER Vault
        SecretManagement vault name. Defaults to 'NSP'.

    .PARAMETER Scope
        'Vault' (default) or 'File' (DPAPI fallback, current user + machine only).

    .EXAMPLE
        Set-NSPSecret -Name 'CW.Control.ApiKey'
        # prompts, stores in the NSP vault

    .EXAMPLE
        Set-NSPSecret -Name 'CW.Control.ApiKey' -Scope File
        # prompts, stores in %LOCALAPPDATA%\NSP\Secrets\CW.Control.ApiKey.sec
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Migration path: a plaintext value handed in by a tech or read from a legacy file must be converted to a SecureString to be stored securely.')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Position = 1)][object]$Secret,
        [string]$Vault = $script:NSPVaultName,
        [ValidateSet('Vault', 'File')][string]$Scope = 'Vault'
    )

    if (-not $PSBoundParameters.ContainsKey('Secret') -or $null -eq $Secret) {
        $secure = Read-Host -Prompt "Enter value for secret '$Name'" -AsSecureString
    } elseif ($Secret -is [System.Security.SecureString]) {
        $secure = $Secret
    } else {
        $secure = ConvertTo-SecureString -String ([string]$Secret) -AsPlainText -Force
    }

    if (-not $secure -or $secure.Length -eq 0) {
        throw "Set-NSPSecret: empty value for '$Name' - nothing stored."
    }

    if ($Scope -eq 'File') {
        $path = Get-NSPSecretFallbackPath -Name $Name
        $dir  = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if ($PSCmdlet.ShouldProcess($path, 'Write DPAPI-encrypted secret file')) {
            ConvertFrom-SecureString -SecureString $secure | Set-Content -LiteralPath $path -NoNewline -Encoding ascii
            Write-Host "Stored '$Name' at $path (DPAPI: current user + this machine only)." -ForegroundColor Green
        }
        return
    }

    if (-not (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretManagement')) {
        throw "SecretManagement is not installed. Run Initialize-NSPSecretStore first, or use -Scope File."
    }
    Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
    if (-not (Get-SecretVault -Name $Vault -ErrorAction SilentlyContinue)) {
        throw "Vault '$Vault' is not registered. Run Initialize-NSPSecretStore first."
    }

    if ($PSCmdlet.ShouldProcess("$Vault\$Name", 'Set-Secret')) {
        Set-Secret -Name $Name -SecureString $secure -Vault $Vault -ErrorAction Stop
        Write-Host "Stored '$Name' in vault '$Vault'." -ForegroundColor Green
    }
}
