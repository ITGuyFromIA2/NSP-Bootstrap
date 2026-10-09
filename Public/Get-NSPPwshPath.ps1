function Get-NSPPwshPath {
    <#
    .SYNOPSIS
        The full path of PowerShell 7 (pwsh.exe), or $null when it is not installed.

    .DESCRIPTION
        Looks on PATH first, then in the standard install folders (Program Files\PowerShell\7 and
        the per-user winget location), so it finds a copy installed moments ago in this session,
        before PATH has been refreshed. Never throws.

    .EXAMPLE
        if (-not (Get-NSPPwshPath)) { Install-NSPPwsh }
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $onPath = Get-Command -Name pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($onPath) { return $onPath.Source }

    $candidates = @(
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe' })
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe' })
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}
