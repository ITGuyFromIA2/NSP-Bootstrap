function Get-NSPSecretFallbackPath {
    <#
    .SYNOPSIS
        Resolves the on-disk path of the DPAPI-encrypted fallback file for a named secret.

    .DESCRIPTION
        Layout:  %LOCALAPPDATA%\NSP\Secrets\<sanitised-name>.sec
        The file holds the output of ConvertFrom-SecureString (DPAPI, current user + current
        machine - not portable to another user or box). This is the last-resort store used when
        SecretManagement is not available; the vault is always preferred. See SECRETS.md.

        Internal helper - not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name
    )

    $safe = ($Name -replace '[^A-Za-z0-9._-]', '_')
    $root = Join-Path $env:LOCALAPPDATA 'NSP\Secrets'
    Join-Path $root ("{0}.sec" -f $safe)
}
