function Update-NSPModule {
    <#
    .SYNOPSIS
        Updates Gallery modules and optionally removes older installed versions.
    .DESCRIPTION
        Accepts names or objects with a Name property, including Get-Module -ListAvailable
        and Get-InstalledModule output. Each distinct name is processed once per pipeline.
        Installs the latest stable PSGallery version unless an equal or newer version is
        already installed in the selected scope. Does not import or unload modules.
        RemoveOld deletes version folders only after verifying the retained installation.
        Loaded copies, flat layouts, links and nonstandard module locations are preserved.
        Removing old versions can affect scripts that require an exact older version.
        WhatIf queries the Gallery and reads local manifests, but changes nothing.
    .PARAMETER Name
        Exact module names, strings from the pipeline, or piped objects with a Name property.
        Wildcards are not accepted here; expand them with Get-Module first.
    .PARAMETER Scope
        CurrentUser (default) or AllUsers (requires elevation to install/remove machine copies).
    .PARAMETER RemoveOld
        Removes versions below the retained version in both standard edition folders.
        CurrentUser cleans the current user's folders only. AllUsers also cleans older
        copies in the current user's folders, never other users' profiles.
    .PARAMETER SkipPublisherCheck
        Passes SkipPublisherCheck to Install-Module when explicitly requested.
    .EXAMPLE
        Update-NSPModule -Name NSP.Console -RemoveOld -WhatIf
    .EXAMPLE
        Get-Module NSP.* -ListAvailable | Update-NSPModule -Scope AllUsers -RemoveOld
    .EXAMPLE
        'NSP.Console', 'NSP.Bootstrap' | Update-NSPModule
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]*$')]
        [string[]]$Name,
        [ValidateSet('CurrentUser', 'AllUsers')][string]$Scope = 'CurrentUser',
        [switch]$RemoveOld,
        [switch]$SkipPublisherCheck
    )
    begin {
        $seen = @{}
        $userRoots = @(Get-NSPModuleUpdateRoot -Scope CurrentUser)
        $installRoots = $userRoots
        if ($Scope -eq 'AllUsers') {
            $installRoots = @(Get-NSPModuleUpdateRoot -Scope AllUsers)
        }
        $cleanupRoots = @($installRoots)
        if ($Scope -eq 'AllUsers') { $cleanupRoots += $userRoots }

        # Inspect only exact standard roots and version folders. Never traverse links.
        $readCopies = {
            param([string[]]$Roots, [string]$ModuleName)
            foreach ($root in $Roots) {
                $base = Join-Path $root $ModuleName
                if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
                $linked = $false
                for ($ancestor = Get-Item -LiteralPath $base -Force -ErrorAction Stop;
                     $null -ne $ancestor; $ancestor = $ancestor.Parent) {
                    if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { $linked = $true; break }
                }
                if ($linked) { throw "Refusing to update linked module location: $base" }
                foreach ($directory in @(Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction Stop)) {
                    $version = $null
                    if (-not [version]::TryParse($directory.Name, [ref]$version)) { continue }
                    if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                        throw "Refusing to update linked version folder: $($directory.FullName)"
                    }
                    $manifest = Join-Path $directory.FullName "$ModuleName.psd1"
                    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
                    if ((Get-Item -LiteralPath $manifest -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                        throw "Refusing to update linked manifest: $manifest"
                    }
                    $data = Import-PowerShellDataFile -LiteralPath $manifest -ErrorAction Stop
                    if ([version]$data.ModuleVersion -ne $version) { continue }
                    [pscustomobject]@{ Version = $version; Path = $directory.FullName }
                }
            }
        }
    }
    process {
        foreach ($moduleName in $Name) {
            if ($seen.ContainsKey($moduleName)) { continue }
            $seen[$moduleName] = $true
            try {
                # Matching Install-NSPModule: TLS 1.2 for the Gallery on Windows PowerShell.
                # Keep even this process-level setting untouched during WhatIf.
                if (-not $WhatIfPreference) {
                    [Net.ServicePointManager]::SecurityProtocol =
                        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                }
                $gallery = Find-Module -Name $moduleName -Repository PSGallery -ErrorAction Stop
                if (-not $gallery -or $gallery.Name -ne $moduleName) { throw "No exact PSGallery match for '$moduleName'." }
                $target = [version]$gallery.Version
                $installed = @(& $readCopies $installRoots $moduleName | Sort-Object Version -Descending)
                if ($installed.Count -and $installed[0].Version -ge $target) {
                    $target = $installed[0].Version
                } else {
                    if ($PSCmdlet.ShouldProcess($moduleName, "Install PSGallery version $target ($Scope)")) {
                        $parameters = @{
                            Name = $moduleName; RequiredVersion = $target.ToString(); Repository = 'PSGallery'
                            Scope = $Scope; Force = $true; ErrorAction = 'Stop'
                        }
                        if ($SkipPublisherCheck) { $parameters.SkipPublisherCheck = $true }
                        Install-Module @parameters
                        $installed = @(& $readCopies $installRoots $moduleName)
                        if (-not @($installed | Where-Object Version -eq $target).Count) {
                            throw "Cannot verify $moduleName $target in $Scope; no old versions removed."
                        }
                    } elseif (-not $WhatIfPreference) { continue }
                }
                if (-not $RemoveOld) { continue }
                # Do not strand an edition by deleting its only copy. Install-Module writes
                # to the calling edition's folder; preserve the other edition before cleanup.
                foreach ($root in $installRoots) {
                    $copies = @(& $readCopies @($root) $moduleName)
                    if (-not $copies.Count -or @($copies | Where-Object Version -ge $target).Count) { continue }
                    if ($target -ne [version]$gallery.Version) {
                        throw "Cannot replace older copies in $root with $target from PSGallery; no old versions removed."
                    }
                    if ($PSCmdlet.ShouldProcess($root, "Save $moduleName $target for this edition before cleanup")) {
                        Save-Module -Name $moduleName -RequiredVersion $target.ToString() -Repository PSGallery -Path $root -Force -ErrorAction Stop
                        if (-not @(& $readCopies @($root) $moduleName | Where-Object Version -ge $target).Count) {
                            throw "Cannot verify $moduleName $target in $root; no old versions removed."
                        }
                    } elseif (-not $WhatIfPreference) { continue }
                }
                $loadedPaths = @(Get-Module -Name $moduleName -All | ForEach-Object ModuleBase)
                foreach ($old in @(& $readCopies $cleanupRoots $moduleName | Where-Object Version -lt $target)) {
                    # A declined secondary save must also decline that folder's cleanup.
                    if (-not $WhatIfPreference) {
                        $root = Split-Path (Split-Path $old.Path -Parent) -Parent
                        if ($installRoots -contains $root -and -not @(& $readCopies @($root) $moduleName | Where-Object Version -ge $target).Count) { continue }
                    }
                    if ($loadedPaths -contains $old.Path) {
                        Write-Warning "Keeping loaded $moduleName $($old.Version): $($old.Path). Retry in a fresh session."
                        continue
                    }
                    if ($PSCmdlet.ShouldProcess($old.Path, "Remove $moduleName $($old.Version); retain $target")) {
                        Remove-Item -LiteralPath $old.Path -Recurse -Force -ErrorAction Stop
                    }
                }
            } catch {
                $PSCmdlet.WriteError($_)
            }
        }
    }
}
