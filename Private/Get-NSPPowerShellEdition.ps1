function Get-NSPPowerShellEdition {
    # 'Core' (PowerShell 7) or 'Desktop' (Windows PowerShell 5.1). A function so tests can mock it.
    if ($PSVersionTable.PSEdition) { [string]$PSVersionTable.PSEdition } else { 'Desktop' }
}
