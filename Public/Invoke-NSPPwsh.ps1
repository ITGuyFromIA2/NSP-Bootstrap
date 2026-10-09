function Invoke-NSPPwsh {
    <#
    .SYNOPSIS
        Relaunches a script or a command in PowerShell 7 (pwsh) when running in Windows PowerShell
        5.1, installing PowerShell 7 first if needed; -Elevated also makes sure it runs elevated.
        Returns $true when it relaunched (the caller should exit), $false when the session is
        already where it should be (the caller should carry on).

    .DESCRIPTION
        The PowerShell 7 counterpart of Invoke-NSPElevated, for tools that should not stay on 5.1
        (Microsoft Graph misbehaves there, and Microsoft is retiring 5.1 for Graph). Elevation and
        edition are separate questions, so this is its own function: Invoke-NSPElevated keeps its
        "same edition" behavior.

          - Already in PowerShell 7 (and elevated, with -Elevated): returns $false.
          - In PowerShell 7, not elevated, with -Elevated: hands over to Invoke-NSPElevated.
          - In 5.1: finds pwsh.exe (Get-NSPPwshPath), installs it when missing (Install-NSPPwsh;
            -NoInstall throws instead), and relaunches into it. With -Elevated and not yet
            elevated, the relaunch asks for elevation (UAC); an elevated session stays elevated
            without a second prompt.

        Same shapes as Invoke-NSPElevated: -ScriptPath (with -ArgumentList, each element quoted)
        or -Command (passed via -EncodedCommand). NSP_NO_ELEVATE=1 keeps everything in the current
        session and returns $false, as it does for Invoke-NSPElevated.

    .PARAMETER ScriptPath
        The .ps1 to relaunch. Usually $PSCommandPath.

    .PARAMETER ArgumentList
        Extra arguments for the relaunched script (ScriptPath form only).

    .PARAMETER Command
        PowerShell command text to run in pwsh (Command form).

    .PARAMETER Elevated
        Also make sure the relaunched session is elevated.

    .PARAMETER NoInstall
        Throw instead of installing PowerShell 7 when it is missing.

    .PARAMETER NoExit
        Keep the new window open after the script/command finishes.

    .PARAMETER Wait
        Block until the new process exits.

    .EXAMPLE
        if (Invoke-NSPPwsh -ScriptPath $PSCommandPath) { exit }

    .EXAMPLE
        if (Invoke-NSPPwsh -Command 'Import-Module NSP.M365.ConditionalAccess; Start-NSPConditionalAccess' -Elevated) { return }
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Script')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Script')][string]$ScriptPath,
        [Parameter(ParameterSetName = 'Script')][string[]]$ArgumentList = @(),
        [Parameter(Mandatory, ParameterSetName = 'Command')][string]$Command,
        [switch]$Elevated,
        [switch]$NoInstall,
        [switch]$NoExit,
        [switch]$Wait
    )

    if ($env:NSP_NO_ELEVATE -eq '1') {
        Write-Verbose 'Invoke-NSPPwsh: NSP_NO_ELEVATE=1 - staying in this session.'
        return $false
    }
    $isAdmin = Test-NSPIsAdmin
    if ((Get-NSPPowerShellEdition) -eq 'Core') {
        if (-not $Elevated -or $isAdmin) { return $false }
        $handOver = @{ NoExit = $NoExit; Wait = $Wait }
        if ($PSCmdlet.ParameterSetName -eq 'Script') { $handOver.ScriptPath = $ScriptPath; $handOver.ArgumentList = $ArgumentList } else { $handOver.Command = $Command }
        return (Invoke-NSPElevated @handOver -WhatIf:$WhatIfPreference)
    }

    $pwsh = Get-NSPPwshPath
    if (-not $pwsh) {
        if ($NoInstall) { throw 'PowerShell 7 is not installed. Install it (Install-NSPPwsh, or https://aka.ms/powershell-release?tag=stable) and run this again.' }
        $pwsh = Install-NSPPwsh
        if (-not $pwsh) {
            # Install-NSPPwsh under -WhatIf installs nothing; report the relaunch that would follow.
            if ($WhatIfPreference) { return $true }
            throw 'PowerShell 7 could not be installed.'
        }
    }

    $psArgs = New-NSPRelaunchArgument -ScriptPath $ScriptPath -ArgumentList $ArgumentList -Command $Command -NoExit:$NoExit
    $how = if ($Elevated -and -not $isAdmin) { 'Relaunch in PowerShell 7, elevated' } else { 'Relaunch in PowerShell 7' }
    if ($PSCmdlet.ShouldProcess($pwsh, "$($how): $($psArgs -join ' ')")) {
        $startArgs = @{ FilePath = $pwsh; ArgumentList = $psArgs }
        if ($Elevated -and -not $isAdmin) { $startArgs['Verb'] = 'RunAs' }
        if ($Wait) { $startArgs['Wait'] = $true }
        Start-Process @startArgs
    }
    return $true
}
