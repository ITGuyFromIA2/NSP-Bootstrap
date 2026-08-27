<#
    NSP.Bootstrap - module loader.

    Dot-sources every .ps1 under Private\ then Public\, and exports only the Public ones.
    This is the standard "one function per file" module layout the NSP toolkit reorg is
    standardising on (see the PoSHRepo ClaudeStuff plan).
#>

$script:NSPVaultName = 'NSP'

$private = @( Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue )
$public  = @( Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue )

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    } catch {
        throw "NSP.Bootstrap: failed to load $($file.FullName): $_"
    }
}

Export-ModuleMember -Function $public.BaseName
