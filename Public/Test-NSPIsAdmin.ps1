function Test-NSPIsAdmin {
    <#
    .SYNOPSIS
        True when the current PowerShell session is running elevated (Windows Administrators role).

    .DESCRIPTION
        One call site for the WindowsPrincipal/IsInRole check that every self-elevating NSP
        dashboard used to carry inline. Returns $false (never throws) on a non-Windows host, where
        the Windows principal APIs don't exist.

    .EXAMPLE
        if (-not (Test-NSPIsAdmin)) { Write-Warning 'Run this elevated.' }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return [bool]$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        Write-Verbose "Test-NSPIsAdmin: Windows principal check unavailable ($_) - reporting not elevated."
        return $false
    }
}
