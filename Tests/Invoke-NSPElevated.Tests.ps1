<#
    Pester 5. Start-Process and Test-NSPIsAdmin are mocked - nothing is ever really launched.
#>

BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'NSP.Bootstrap.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module NSP.Bootstrap -Force -ErrorAction SilentlyContinue
}

Describe 'Test-NSPIsAdmin' {
    It 'returns a boolean' {
        Test-NSPIsAdmin | Should -BeOfType [bool]
    }
}

Describe 'Invoke-NSPElevated' {

    BeforeEach {
        Mock -ModuleName NSP.Bootstrap Start-Process { }
    }

    It 'returns $false and launches nothing when already elevated' {
        Mock -ModuleName NSP.Bootstrap Test-NSPIsAdmin { $true }
        Invoke-NSPElevated -ScriptPath 'C:\x.ps1' | Should -BeFalse
        Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 0 -Exactly
    }

    Context 'not elevated' {
        BeforeEach {
            Mock -ModuleName NSP.Bootstrap Test-NSPIsAdmin { $false }
        }

        It 'relaunches a script with RunAs and returns $true' {
            Invoke-NSPElevated -ScriptPath 'C:\Some Dir\x.ps1' -ArgumentList '-ShimPath', 'C:\a b\shim.ps1' | Should -BeTrue
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 1 -Exactly -ParameterFilter {
                $Verb -eq 'RunAs' -and
                ($ArgumentList -join ' ') -eq '-NoProfile -ExecutionPolicy Bypass -File "C:\Some Dir\x.ps1" -ShimPath "C:\a b\shim.ps1"'
            }
        }

        It 'encodes a command so quotes and $ survive' {
            $cmd = "Import-Module NSP.X; Start-NSPX -Seed '{""a"":""`$b""}'"
            Invoke-NSPElevated -Command $cmd | Should -BeTrue
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 1 -Exactly -ParameterFilter {
                $i = [array]::IndexOf($ArgumentList, '-EncodedCommand')
                $i -ge 0 -and [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[$i + 1])) -eq $cmd
            }
        }

        It 'honours -NoExit, -Wait and -PowerShellPath' {
            Invoke-NSPElevated -Command 'x' -NoExit -Wait -PowerShellPath 'pwsh.exe' | Out-Null
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'pwsh.exe' -and $Wait -and ($ArgumentList -contains '-NoExit')
            }
        }

        It 'never relaunches when NSP_NO_ELEVATE is 1' {
            $env:NSP_NO_ELEVATE = '1'
            try { Invoke-NSPElevated -Command 'x' | Should -BeFalse }
            finally { Remove-Item Env:\NSP_NO_ELEVATE }
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 0 -Exactly
        }

        It 'launches nothing under -WhatIf but still reports a relaunch' {
            Invoke-NSPElevated -Command 'x' -WhatIf | Should -BeTrue
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 0 -Exactly
        }
    }
}

Describe 'Invoke-NSPPwsh' {

    BeforeEach {
        Mock -ModuleName NSP.Bootstrap Start-Process { }
        Mock -ModuleName NSP.Bootstrap Install-NSPPwsh { 'C:\Program Files\PowerShell\7\pwsh.exe' }
        Mock -ModuleName NSP.Bootstrap Get-NSPPwshPath { 'C:\Program Files\PowerShell\7\pwsh.exe' }
        Mock -ModuleName NSP.Bootstrap Test-NSPIsAdmin { $false }
    }

    Context 'in PowerShell 7' {
        BeforeEach { Mock -ModuleName NSP.Bootstrap Get-NSPPowerShellEdition { 'Core' } }

        It 'stays put: returns $false and launches nothing' {
            Invoke-NSPPwsh -ScriptPath 'C:\x.ps1' | Should -BeFalse
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 0 -Exactly
        }

        It 'stays put with -Elevated when already elevated' {
            Mock -ModuleName NSP.Bootstrap Test-NSPIsAdmin { $true }
            Invoke-NSPPwsh -ScriptPath 'C:\x.ps1' -Elevated | Should -BeFalse
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 0 -Exactly
        }

        It 'elevates in PowerShell 7 with -Elevated when not elevated' {
            Invoke-NSPPwsh -ScriptPath 'C:\x.ps1' -ArgumentList '-A', 'b' -Elevated | Should -BeTrue
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'pwsh.exe' -and $Verb -eq 'RunAs' -and ($ArgumentList -join ' ') -eq '-NoProfile -ExecutionPolicy Bypass -File C:\x.ps1 -A b'
            }
        }
    }

    Context 'in Windows PowerShell 5.1' {
        BeforeEach { Mock -ModuleName NSP.Bootstrap Get-NSPPowerShellEdition { 'Desktop' } }

        It 'relaunches a script in pwsh without elevating, and returns $true' {
            Invoke-NSPPwsh -ScriptPath 'C:\Some Dir\x.ps1' -ArgumentList '-Tenant', 'contoso' | Should -BeTrue
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'C:\Program Files\PowerShell\7\pwsh.exe' -and -not $Verb -and
                ($ArgumentList -join ' ') -eq '-NoProfile -ExecutionPolicy Bypass -File "C:\Some Dir\x.ps1" -Tenant contoso'
            }
            Should -Invoke -ModuleName NSP.Bootstrap Install-NSPPwsh -Times 0 -Exactly
        }

        It 'asks for elevation with -Elevated, but not a second time when already elevated' {
            Invoke-NSPPwsh -Command 'x' -Elevated | Should -BeTrue
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 1 -Exactly -ParameterFilter { $Verb -eq 'RunAs' }
            Mock -ModuleName NSP.Bootstrap Test-NSPIsAdmin { $true }
            Invoke-NSPPwsh -Command 'x' -Elevated | Should -BeTrue
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 1 -Exactly -ParameterFilter { -not $Verb }
        }

        It 'encodes a command so quotes and $ survive' {
            $cmd = "Import-Module NSP.X; Start-NSPX -Seed '{""a"":""`$b""}'"
            Invoke-NSPPwsh -Command $cmd -NoExit -Wait | Should -BeTrue
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 1 -Exactly -ParameterFilter {
                $i = [array]::IndexOf($ArgumentList, '-EncodedCommand')
                $Wait -and ($ArgumentList -contains '-NoExit') -and
                $i -ge 0 -and [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[$i + 1])) -eq $cmd
            }
        }

        It 'installs PowerShell 7 when it is missing, or throws with -NoInstall' {
            Mock -ModuleName NSP.Bootstrap Get-NSPPwshPath { $null }
            { Invoke-NSPPwsh -Command 'x' -NoInstall } | Should -Throw '*not installed*'
            Should -Invoke -ModuleName NSP.Bootstrap Install-NSPPwsh -Times 0 -Exactly
            Invoke-NSPPwsh -Command 'x' | Should -BeTrue
            Should -Invoke -ModuleName NSP.Bootstrap Install-NSPPwsh -Times 1 -Exactly
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'C:\Program Files\PowerShell\7\pwsh.exe' }
        }

        It 'never relaunches when NSP_NO_ELEVATE is 1' {
            $env:NSP_NO_ELEVATE = '1'
            try { Invoke-NSPPwsh -Command 'x' -Elevated | Should -BeFalse }
            finally { Remove-Item Env:\NSP_NO_ELEVATE }
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 0 -Exactly
        }

        It 'launches nothing under -WhatIf but still reports a relaunch' {
            Invoke-NSPPwsh -Command 'x' -WhatIf | Should -BeTrue
            Should -Invoke -ModuleName NSP.Bootstrap Start-Process -Times 0 -Exactly
        }
    }
}

Describe 'Install-NSPPwsh' {
    BeforeEach {
        Mock -ModuleName NSP.Bootstrap Start-Process { }
        Mock -ModuleName NSP.Bootstrap Invoke-RestMethod { throw 'no network in tests' }
    }

    It 'installs nothing when PowerShell 7 is already there' {
        Mock -ModuleName NSP.Bootstrap Get-NSPPwshPath { 'C:\pwsh.exe' }
        Install-NSPPwsh | Should -Be 'C:\pwsh.exe'
        Should -Invoke -ModuleName NSP.Bootstrap Invoke-RestMethod -Times 0 -Exactly
    }

    It 'refuses the MSI path without elevation when there is no winget' {
        Mock -ModuleName NSP.Bootstrap Get-NSPPwshPath { $null }
        Mock -ModuleName NSP.Bootstrap Get-Command { $null } -ParameterFilter { $Name -eq 'winget.exe' }
        Mock -ModuleName NSP.Bootstrap Test-NSPIsAdmin { $false }
        { Install-NSPPwsh } | Should -Throw '*not elevated*'
        Should -Invoke -ModuleName NSP.Bootstrap Invoke-RestMethod -Times 0 -Exactly
    }
}

Describe 'Get-NSPPwshPath' {
    It 'returns a path or $null, never throws' {
        { Get-NSPPwshPath } | Should -Not -Throw
        $path = Get-NSPPwshPath
        if ($path) { $path | Should -Match 'pwsh\.exe$' }
    }
}

Describe 'ConvertTo-NSPQuotedArgument (private)' {
    It 'quotes <In> as <Out>' -ForEach @(
        @{ In = '-ShimPath';       Out = '-ShimPath' }
        @{ In = 'C:\a b\x.ps1';    Out = '"C:\a b\x.ps1"' }
        @{ In = '';                Out = '""' }
        @{ In = 'say "hi"';        Out = '"say \"hi\""' }
        @{ In = 'C:\dir with sp\'; Out = '"C:\dir with sp\\"' }
    ) {
        InModuleScope NSP.Bootstrap -Parameters @{ In = $In } { param($In) ConvertTo-NSPQuotedArgument $In } | Should -Be $Out
    }
}
