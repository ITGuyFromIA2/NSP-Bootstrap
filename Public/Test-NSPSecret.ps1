function Test-NSPSecret {
    <#
    .SYNOPSIS
        Preflight check for one named secret: can it actually be read right now, which source
        would win, and why not if it can't. Never returns the value.

    .DESCRIPTION
        Test-NSPSecretStore answers "is the store healthy" in general. This answers the narrower,
        more common startup question: "can THIS toolkit read the specific secrets it needs, right
        now, before it does any work." A script can loop its required secret names through this at
        startup and report something actionable - "vault is locked", "secret missing", "vault not
        registered" - instead of failing deep into a run on whatever Get-NSPSecret call happens
        first.

        Walks the same three sources as Get-NSPSecret, in the same order, but never calls
        Get-Secret / reads a DPAPI file's contents - only existence/reachability checks, so the
        value itself is never touched:

          1. Environment variable  NSP_SECRET_<NAME>.
          2. SecretManagement vault (default 'NSP'). Distinguishes "vault not registered" from
             "vault registered but not reachable (locked / misconfigured)" from "reachable but
             this name isn't in it" - those are three different fixes.
          3. DPAPI fallback file  %LOCALAPPDATA%\NSP\Secrets\<name>.sec  (existence only).

        Reason is $null when Available is $true.

    .PARAMETER Name
        One or more secret names to check, e.g. 'CW.Control.ApiKey'. Accepts pipeline input so a
        toolkit can check a whole credential set in one call:
        'A','B','C' | Test-NSPSecret

    .PARAMETER Vault
        SecretManagement vault name. Defaults to 'NSP'.

    .EXAMPLE
        Test-NSPSecret -Name 'CW.Automate.ClientId'

    .EXAMPLE
        # startup preflight for a toolkit that needs four Automate credentials
        $required = 'CW.Automate.ClientId', 'CW.Automate.User', 'CW.Automate.Password', 'CW.Automate.TotpSeed'
        $missing = $required | Test-NSPSecret | Where-Object { -not $_.Available }
        if ($missing) {
            $missing | ForEach-Object { Write-Warning "$($_.Name): $($_.Reason)" }
            throw "Missing required secrets - see warnings above."
        }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [string]$Vault = $script:NSPVaultName
    )

    begin {
        # Vault reachability doesn't depend on which secret name we're asked about, so it's
        # resolved once here rather than once per -Name when several are piped in.
        $vaultModuleAvailable = [bool](Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretManagement')
        $vaultReachable  = $false
        $vaultStateReason = $null

        if ($vaultModuleAvailable) {
            try { Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop } catch {
                $vaultStateReason = "SecretManagement is installed but failed to import: $($_.Exception.Message)"
            }

            if (-not $vaultStateReason) {
                $vaultInfo = $null
                try { $vaultInfo = Get-SecretVault -Name $Vault -ErrorAction Stop } catch { $vaultInfo = $null }

                if (-not $vaultInfo) {
                    $vaultStateReason = "vault '$Vault' is not registered (run Initialize-NSPSecretStore)"
                } else {
                    try {
                        # Existence probe only - result discarded, matches Test-NSPSecretStore's
                        # own reachability check. This is what surfaces "vault is locked" as
                        # distinct from "secret missing".
                        $null = Get-SecretInfo -Vault $Vault -ErrorAction Stop
                        $vaultReachable = $true
                    } catch {
                        $vaultStateReason = "vault '$Vault' is registered but not reachable right now - locked or misconfigured: $($_.Exception.Message)"
                    }
                }
            }
        } else {
            $vaultStateReason = 'SecretManagement module is not installed'
        }
    }

    process {
        foreach ($oneName in $Name) {
            $envName = 'NSP_SECRET_' + (($oneName -replace '[^A-Za-z0-9]', '_').ToUpperInvariant())
            if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($envName))) {
                [pscustomobject]@{
                    Name      = $oneName
                    Available = $true
                    Source    = 'EnvironmentVariable'
                    Detail    = $envName
                    Reason    = $null
                }
                continue
            }

            if ($vaultReachable -and (Get-SecretInfo -Name $oneName -Vault $Vault -ErrorAction SilentlyContinue)) {
                [pscustomobject]@{
                    Name      = $oneName
                    Available = $true
                    Source    = 'Vault'
                    Detail    = $Vault
                    Reason    = $null
                }
                continue
            }

            $path = Get-NSPSecretFallbackPath -Name $oneName
            if (Test-Path -LiteralPath $path) {
                [pscustomobject]@{
                    Name      = $oneName
                    Available = $true
                    Source    = 'File'
                    Detail    = $path
                    Reason    = $null
                }
                continue
            }

            $vaultPart = if ($vaultReachable) { "not present in vault '$Vault'" } else { $vaultStateReason }
            [pscustomobject]@{
                Name      = $oneName
                Available = $false
                Source    = 'None'
                Detail    = $null
                Reason    = "Not found: $vaultPart; no DPAPI fallback file either. Store it: Set-NSPSecret -Name '$oneName'."
            }
        }
    }
}
