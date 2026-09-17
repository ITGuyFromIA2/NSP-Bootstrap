function Get-NSPSecretInfo {
    <#
    .SYNOPSIS
        Lists secrets NSP.Bootstrap knows about - names and where they're stored, never values.

    .DESCRIPTION
        Reports across all three of Get-NSPSecret's resolution sources:
          - the SecretManagement vault (Get-SecretInfo, if the module/vault are present)
          - the DPAPI fallback directory (%LOCALAPPDATA%\NSP\Secrets\*.sec)
          - NSP_SECRET_* environment variables

        Env var names are a lossy mangling of the original secret Name (every character except
        letters/digits becomes _), so there's no way to recover the original Name from one - the
        Name column shows the raw environment variable instead, and -Name filtering against an
        environment entry matches the same mangled form Get-NSPSecret would produce, not the
        literal Name.

    .PARAMETER Name
        Filter by name, wildcards allowed (e.g. 'CW.*'). Matches vault/file entries by their real
        name. Defaults to '*' (everything).

    .PARAMETER Vault
        SecretManagement vault name. Defaults to 'NSP'.

    .EXAMPLE
        Get-NSPSecretInfo

    .EXAMPLE
        Get-NSPSecretInfo -Name 'CW.*' | Format-Table
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Name = '*',
        [string]$Vault = $script:NSPVaultName
    )

    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    # --- SecretManagement vault ---------------------------------------------------
    if (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretManagement') {
        try { Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop } catch {
            Write-Verbose "Get-NSPSecretInfo: SecretManagement present but failed to import ($_)."
        }
        $vaultPresent = $false
        try   { $vaultPresent = [bool](Get-SecretVault -Name $Vault -ErrorAction SilentlyContinue) }
        catch { $vaultPresent = $false }

        if ($vaultPresent) {
            foreach ($info in (Get-SecretInfo -Name $Name -Vault $Vault -ErrorAction SilentlyContinue)) {
                $results.Add([pscustomobject]@{
                    Name   = $info.Name
                    Source = 'Vault'
                    Detail = $Vault
                })
            }
        }
    }

    # --- DPAPI fallback files ------------------------------------------------------
    $secretsDir = Join-Path $env:LOCALAPPDATA 'NSP\Secrets'
    if (Test-Path -LiteralPath $secretsDir) {
        foreach ($file in (Get-ChildItem -LiteralPath $secretsDir -Filter '*.sec' -File -ErrorAction SilentlyContinue)) {
            if ($file.BaseName -like $Name) {
                $results.Add([pscustomobject]@{
                    Name   = $file.BaseName
                    Source = 'File'
                    Detail = $file.FullName
                })
            }
        }
    }

    # --- Environment variables -------------------------------------------------------
    # Preserve * and ? in -Name so the default '*' (and any wildcard filter) still means
    # "wildcard" after mangling, instead of becoming a literal underscore like every other
    # non-alphanumeric character does.
    $envPattern = 'NSP_SECRET_' + (($Name -replace '[^A-Za-z0-9*?]', '_').ToUpperInvariant())
    foreach ($item in (Get-ChildItem -Path 'Env:NSP_SECRET_*' -ErrorAction SilentlyContinue)) {
        if ($item.Name -like $envPattern) {
            $results.Add([pscustomobject]@{
                Name   = $item.Name
                Source = 'EnvironmentVariable'
                Detail = $null
            })
        }
    }

    $results | Sort-Object Source, Name
}
