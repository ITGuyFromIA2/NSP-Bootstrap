Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'NSP.Bootstrap.psd1') -Force -ErrorAction Stop
BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'NSP.Bootstrap.psd1') -Force -ErrorAction Stop
}
AfterAll { Remove-Module NSP.Bootstrap -Force -ErrorAction SilentlyContinue }

Describe 'Update-NSPModule offline update and cleanup' {
    InModuleScope NSP.Bootstrap {
        BeforeAll {
            function New-TestModuleCopy {
                param($Root, $Version)
                $folder = Join-Path $Root "NSP.Example\$Version"
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $folder 'NSP.Example.psd1') -Value "@{ModuleVersion='$Version'}"
                $folder
            }
        }
        BeforeEach {
            $script:userRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            $script:machineRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            Mock Get-NSPModuleUpdateRoot { if ($Scope -eq 'AllUsers') { $script:machineRoot } else { $script:userRoot } }
            Mock Find-Module { [pscustomobject]@{Name='NSP.Example';Version=[version]'2.0.0'} }
            Mock Install-Module {
                $root = $script:userRoot
                if ($Scope -eq 'AllUsers') { $root = $script:machineRoot }
                New-TestModuleCopy $root $RequiredVersion | Out-Null
            }
            Mock Get-Module { @() }
            Mock Save-Module { New-TestModuleCopy $Path $RequiredVersion | Out-Null }
        }
        It 'accepts strings and deduplicates case-insensitively' {
            'NSP.Example','nsp.example' | Update-NSPModule
            Should -Invoke Find-Module -Times 1 -Exactly
            Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter { $RequiredVersion -eq '2.0.0' -and $Scope -eq 'CurrentUser' }
        }
        It 'accepts objects by Name property' {
            [pscustomobject]@{Name='NSP.Example';Version='1.0.0'} | Update-NSPModule
            Should -Invoke Find-Module -Times 1 -ParameterFilter { $Name -eq 'NSP.Example' }
        }
        It 'accepts real PSModuleInfo objects and deduplicates versions' {
            $old = New-TestModuleCopy $script:userRoot '1.0.0'
            $new = New-TestModuleCopy $script:userRoot '1.1.0'
            @((Test-ModuleManifest (Join-Path $old 'NSP.Example.psd1')), (Test-ModuleManifest (Join-Path $new 'NSP.Example.psd1'))) |
                Update-NSPModule -RemoveOld
            Should -Invoke Find-Module -Times 1 -Exactly
            Test-Path $old | Should -BeFalse
            Test-Path $new | Should -BeFalse
        }
        It 'preserves old versions unless RemoveOld is supplied' {
            $old = New-TestModuleCopy $script:userRoot '1.0.0'
            Update-NSPModule NSP.Example
            Test-Path $old | Should -BeTrue
        }
        It 'cleans current-user old versions but leaves machine copies alone' {
            $user = New-TestModuleCopy $script:userRoot '1.0.0'
            $machine = New-TestModuleCopy $script:machineRoot '1.0.0'
            Update-NSPModule NSP.Example -RemoveOld
            Test-Path $user | Should -BeFalse
            Test-Path $machine | Should -BeTrue
        }
        It 'AllUsers installs machine-wide then cleans both scopes, preserving equal and newer user copies' {
            $user = New-TestModuleCopy $script:userRoot '1.0.0'
            $machine = New-TestModuleCopy $script:machineRoot '1.0.0'
            $equal = New-TestModuleCopy $script:userRoot '2.0.0'
            $newer = New-TestModuleCopy $script:userRoot '3.0.0'
            Update-NSPModule NSP.Example -Scope AllUsers -RemoveOld
            Should -Invoke Install-Module -Times 1 -ParameterFilter { $Scope -eq 'AllUsers' }
            Test-Path $user | Should -BeFalse
            Test-Path $machine | Should -BeFalse
            Test-Path $equal | Should -BeTrue
            Test-Path $newer | Should -BeTrue
        }
        It 'cleans even when the retained version was already installed and never downgrades' {
            $old = New-TestModuleCopy $script:userRoot '1.0.0'
            $latest = New-TestModuleCopy $script:userRoot '3.0.0'
            Update-NSPModule NSP.Example -RemoveOld
            Should -Invoke Install-Module -Times 0
            Test-Path $old | Should -BeFalse
            Test-Path $latest | Should -BeTrue
        }
        It 'WhatIf neither installs nor deletes when an update is needed' {
            $old = New-TestModuleCopy $script:userRoot '1.0.0'
            Update-NSPModule NSP.Example -RemoveOld -WhatIf
            Should -Invoke Install-Module -Times 0
            Test-Path $old | Should -BeTrue
        }
        It 'WhatIf preserves old versions when already up to date' {
            $old = New-TestModuleCopy $script:userRoot '1.0.0'
            New-TestModuleCopy $script:userRoot '2.0.0' | Out-Null
            Update-NSPModule NSP.Example -RemoveOld -WhatIf
            Test-Path $old | Should -BeTrue
        }
        It 'does not clean up after an installation failure' {
            $old = New-TestModuleCopy $script:userRoot '1.0.0'
            Mock Install-Module { throw 'Synthetic install failure' }
            { Update-NSPModule NSP.Example -RemoveOld -ErrorAction Stop } | Should -Throw '*Synthetic install failure*'
            Test-Path $old | Should -BeTrue
        }
        It 'does not clean up if installation did not create a verified copy' {
            $old = New-TestModuleCopy $script:userRoot '1.0.0'
            Mock Install-Module { }
            { Update-NSPModule NSP.Example -RemoveOld -ErrorAction Stop } | Should -Throw '*Cannot verify*'
            Test-Path $old | Should -BeTrue
        }
        It 'does not clean up if Gallery lookup fails' {
            $old = New-TestModuleCopy $script:userRoot '1.0.0'
            Mock Find-Module { throw 'Synthetic Gallery failure' }
            { Update-NSPModule NSP.Example -RemoveOld -ErrorAction Stop } | Should -Throw '*Synthetic Gallery failure*'
            Test-Path $old | Should -BeTrue
        }
        It 'keeps loaded old versions' {
            $script:loaded = New-TestModuleCopy $script:userRoot '1.0.0'
            Mock Get-Module { [pscustomobject]@{ModuleBase=$script:loaded} }
            Update-NSPModule NSP.Example -RemoveOld -WarningAction SilentlyContinue
            Test-Path $script:loaded | Should -BeTrue
        }
        It 'leaves mismatched manifests and flat layouts alone' {
            $odd = New-TestModuleCopy $script:userRoot '1.0.0'
            Set-Content (Join-Path $odd 'NSP.Example.psd1') "@{ModuleVersion='9.0.0'}"
            $flat = Join-Path $script:userRoot 'NSP.Example\NSP.Example.psd1'
            Set-Content $flat "@{ModuleVersion='0.5.0'}"
            Update-NSPModule NSP.Example -RemoveOld
            Test-Path $odd | Should -BeTrue
            Test-Path $flat | Should -BeTrue
        }
        It 'rejects wildcard names before querying the Gallery' {
            { Update-NSPModule 'NSP.*' -ErrorAction Stop } | Should -Throw
            Should -Invoke Find-Module -Times 0
        }
        It 'cleans both edition folders in both scopes during AllUsers cleanup' {
            $script:userOther = Join-Path $TestDrive 'user-other'
            $script:machineOther = Join-Path $TestDrive 'machine-other'
            Mock Get-NSPModuleUpdateRoot {
                if ($Scope -eq 'AllUsers') { $script:machineRoot; $script:machineOther }
                else { $script:userRoot; $script:userOther }
            }
            $oldCopies = @($script:userRoot, $script:userOther, $script:machineRoot, $script:machineOther |
                ForEach-Object { New-TestModuleCopy $_ '1.0.0' })
            Update-NSPModule NSP.Example -Scope AllUsers -RemoveOld
            foreach ($old in $oldCopies) { Test-Path $old | Should -BeFalse }
            Test-Path (Join-Path $script:machineOther 'NSP.Example\2.0.0\NSP.Example.psd1') | Should -BeTrue
        }
        It 'preserves a linked module location' {
            $old = New-TestModuleCopy $script:userRoot '1.0.0'
            New-TestModuleCopy $script:userRoot '2.0.0' | Out-Null
            $script:linkedBase = Split-Path $old -Parent
            Mock Get-Item {
                [pscustomobject]@{Attributes=[IO.FileAttributes]::ReparsePoint;Parent=$null}
            } -ParameterFilter { $LiteralPath -eq $script:linkedBase }
            Mock Install-Module { }
            Update-NSPModule NSP.Example -RemoveOld -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Test-Path $old | Should -BeTrue
            Should -Invoke Install-Module -Times 0
        }
        It 'preserves a linked version folder' {
            $old = New-TestModuleCopy $script:userRoot '1.0.0'
            New-TestModuleCopy $script:userRoot '2.0.0' | Out-Null
            $script:fakeOld = [pscustomobject]@{Name='1.0.0';FullName=$old;Attributes=[IO.FileAttributes]::ReparsePoint}
            Mock Get-ChildItem { $script:fakeOld }
            Mock Install-Module { }
            Update-NSPModule NSP.Example -RemoveOld -ErrorAction SilentlyContinue
            Test-Path $old | Should -BeTrue
            Should -Invoke Install-Module -Times 0
        }
        It 'does not delete anything if the other edition cannot be updated' {
            $script:machineOther = Join-Path $TestDrive 'machine-failure'
            Mock Get-NSPModuleUpdateRoot {
                if ($Scope -eq 'AllUsers') { $script:machineRoot; $script:machineOther }
                else { $script:userRoot }
            }
            $old = New-TestModuleCopy $script:machineOther '1.0.0'
            $user = New-TestModuleCopy $script:userRoot '1.0.0'
            Mock Save-Module { throw 'Synthetic secondary install failure' }
            { Update-NSPModule NSP.Example -Scope AllUsers -RemoveOld -ErrorAction Stop } | Should -Throw '*Synthetic secondary install failure*'
            Test-Path $old | Should -BeTrue
            Test-Path $user | Should -BeTrue
        }
    }
}
