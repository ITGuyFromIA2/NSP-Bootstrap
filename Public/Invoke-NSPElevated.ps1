function Invoke-NSPElevated {
    <#
    .SYNOPSIS
        Relaunches a script or a command in an elevated PowerShell (UAC prompt) when the current
        session isn't already elevated. Returns $true when it relaunched (the caller should exit),
        $false when the session is already elevated (the caller should carry on).

    .DESCRIPTION
        Replaces the "IsInRole check -> Start-Process powershell.exe -Verb RunAs -> exit" block every
        NSP dashboard and shim carried inline. Two shapes:

          -ScriptPath  relaunch a .ps1 file (the classic self-elevating script). -ArgumentList is
                       appended after -File <path>; each element is quoted for you.
          -Command     relaunch an arbitrary command - typically
                       'Import-Module NSP.X; Start-NSPXManager' for a module-hosted dashboard, which
                       has no script path to re-run. Passed via -EncodedCommand, so quotes, $ and
                       newlines in the command survive the hop untouched.

        The relaunch uses the same PowerShell edition as the caller (powershell.exe from 5.1,
        pwsh.exe from 7+) unless -PowerShellPath overrides it.

        When the environment variable NSP_NO_ELEVATE is '1' it never relaunches and returns $false,
        so a launcher run with -NoElevate (or a test) keeps every tool it starts in the same session.

    .PARAMETER ScriptPath
        The .ps1 to relaunch elevated. Usually $PSCommandPath.

    .PARAMETER ArgumentList
        Extra arguments for the relaunched script (ScriptPath form only).

    .PARAMETER Command
        PowerShell command text to run elevated (Command form).

    .PARAMETER NoExit
        Keep the elevated window open after the script/command finishes.

    .PARAMETER Wait
        Block until the elevated process exits.

    .PARAMETER PowerShellPath
        Override the PowerShell executable used for the relaunch.

    .EXAMPLE
        if (Invoke-NSPElevated -ScriptPath $PSCommandPath -ArgumentList '-ShimPath', $ShimPath) { exit }

    .EXAMPLE
        if (Invoke-NSPElevated -Command 'Import-Module NSP.ActiveDirectory; Start-NSPADManager') { return }
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Script')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Script')][string]$ScriptPath,
        [Parameter(ParameterSetName = 'Script')][string[]]$ArgumentList = @(),
        [Parameter(Mandatory, ParameterSetName = 'Command')][string]$Command,
        [switch]$NoExit,
        [switch]$Wait,
        [string]$PowerShellPath
    )

    if (Test-NSPIsAdmin) { return $false }
    if ($env:NSP_NO_ELEVATE -eq '1') {
        Write-Verbose 'Invoke-NSPElevated: NSP_NO_ELEVATE=1 - staying in this session.'
        return $false
    }

    if (-not $PowerShellPath) {
        $PowerShellPath = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    }

    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($NoExit) { $psArgs += '-NoExit' }

    if ($PSCmdlet.ParameterSetName -eq 'Script') {
        $psArgs += @('-File', (ConvertTo-NSPQuotedArgument $ScriptPath))
        foreach ($a in $ArgumentList) { $psArgs += (ConvertTo-NSPQuotedArgument $a) }
    } else {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
        $psArgs += @('-EncodedCommand', $encoded)
    }

    if ($PSCmdlet.ShouldProcess($PowerShellPath, "Relaunch elevated: $($psArgs -join ' ')")) {
        $startArgs = @{ FilePath = $PowerShellPath; ArgumentList = $psArgs; Verb = 'RunAs' }
        if ($Wait) { $startArgs['Wait'] = $true }
        Start-Process @startArgs
    }
    return $true
}
