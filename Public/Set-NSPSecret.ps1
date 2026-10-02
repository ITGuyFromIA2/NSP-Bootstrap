function Set-NSPSecret {
    <#
    .SYNOPSIS
        Stores (or replaces) a named secret.

    .DESCRIPTION
        Writes to the SecretManagement vault (default 'NSP') unless -Scope File is given, which
        writes the DPAPI fallback file instead.

        If -Secret is omitted the value is read with Read-Host -AsSecureString, so it never lands
        in shell history, a script file, or a transcript. Prefer that interactively.

        That prompt is the wrong default for CI or a scheduled script, though - it would hang
        waiting on a console that isn't there. Pass -NonInteractive to turn a missing -Secret into
        an immediate, clear throw instead of a prompt.

    .PARAMETER Name
        Secret name, e.g. 'CW.Control.ApiKey'.

    .PARAMETER Secret
        The value: a [string], a [SecureString], or omitted (prompt, unless -NonInteractive). A
        plain string is accepted for scripted migration but is the least safe path.

    .PARAMETER Vault
        SecretManagement vault name. Defaults to 'NSP'.

    .PARAMETER Scope
        'Vault' (default) or 'File' (DPAPI fallback, current user + machine only).

    .PARAMETER NonInteractive
        Throw instead of prompting when -Secret is omitted. For CI/scheduled use, where a
        Read-Host prompt would just hang.

    .EXAMPLE
        Set-NSPSecret -Name 'CW.Control.ApiKey'
        # prompts, stores in the NSP vault

    .EXAMPLE
        Set-NSPSecret -Name 'CW.Control.ApiKey' -Scope File
        # prompts, stores in %LOCALAPPDATA%\NSP\Secrets\CW.Control.ApiKey.sec

    .EXAMPLE
        Set-NSPSecret -Name 'CI.Deploy.Token' -Secret $token -NonInteractive
        # scripted: fails fast if $token is somehow empty/unset, instead of hanging on a prompt
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Migration path: a plaintext value handed in by a tech or read from a legacy file must be converted to a SecureString to be stored securely.')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Position = 1)][object]$Secret,
        [string]$Vault = $script:NSPVaultName,
        [ValidateSet('Vault', 'File')][string]$Scope = 'Vault',
        [switch]$NonInteractive
    )

    if (-not $PSBoundParameters.ContainsKey('Secret') -or $null -eq $Secret) {
        if ($NonInteractive) {
            throw "Set-NSPSecret: -NonInteractive requires -Secret - no value was supplied for '$Name' and prompting is disabled."
        }
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
        if ($PSCmdlet.ShouldProcess($path, 'Write DPAPI-encrypted secret file')) {
            # Every step terminates on failure, and success is only reported after the stored value
            # reads back and decrypts to what was given (security review FI-4: an access-denied
            # write used to be followed by the green "Stored" line).
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
            $tmp = "$path.tmp"
            try {
                [IO.File]::WriteAllText($tmp, (ConvertFrom-SecureString -SecureString $secure), [Text.Encoding]::ASCII)
                Move-Item -LiteralPath $tmp -Destination $path -Force -ErrorAction Stop
            } finally {
                if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            }
            $readBack = ConvertTo-SecureString -String ([IO.File]::ReadAllText($path).Trim()) -ErrorAction Stop
            $expected = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            $actual = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($readBack)
            try {
                $same = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($expected) -ceq [Runtime.InteropServices.Marshal]::PtrToStringBSTR($actual)
            } finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($expected)
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($actual)
            }
            if (-not $same) { throw "Set-NSPSecret: '$Name' was written to $path but does not read back as the value given - not stored." }
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
