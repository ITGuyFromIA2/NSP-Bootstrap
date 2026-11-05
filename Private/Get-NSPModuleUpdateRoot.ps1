function Get-NSPModuleUpdateRoot {
    [CmdletBinding()]
    param([ValidateSet('CurrentUser', 'AllUsers')][string]$Scope)
    $base = [Environment]::GetFolderPath('MyDocuments')
    if ($Scope -eq 'AllUsers') { $base = $env:ProgramFiles }
    if (-not $base) { throw "Cannot locate standard module folders for $Scope." }
    Join-Path $base 'WindowsPowerShell\Modules'
    Join-Path $base 'PowerShell\Modules'
}
