function Remove-NSPSecret {
    <#
    .SYNOPSIS
        Removes a named secret from the vault, the DPAPI fallback file, or both.

    .PARAMETER Name
        Secret name.

    .PARAMETER Vault
        SecretManagement vault name. Defaults to 'NSP'.

    .PARAMETER Scope
        'Vault', 'File', or 'Both' (default).

    .EXAMPLE
        Remove-NSPSecret -Name 'Old.ApiKey'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string]$Vault = $script:NSPVaultName,
        [ValidateSet('Vault', 'File', 'Both')][string]$Scope = 'Both'
    )

    if ($Scope -in 'Vault', 'Both') {
        if (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretManagement') {
            Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
            if ((Get-SecretVault -Name $Vault -ErrorAction SilentlyContinue) -and
                (Get-SecretInfo -Name $Name -Vault $Vault -ErrorAction SilentlyContinue)) {
                if ($PSCmdlet.ShouldProcess("$Vault\$Name", 'Remove-Secret')) {
                    Remove-Secret -Name $Name -Vault $Vault -ErrorAction Stop
                    Write-Verbose "Removed '$Name' from vault '$Vault'."
                }
            }
        }
    }

    if ($Scope -in 'File', 'Both') {
        $path = Get-NSPSecretFallbackPath -Name $Name
        if (Test-Path -LiteralPath $path) {
            if ($PSCmdlet.ShouldProcess($path, 'Delete DPAPI secret file')) {
                Remove-Item -LiteralPath $path -Force
                Write-Verbose "Deleted $path."
            }
        }
    }
}
