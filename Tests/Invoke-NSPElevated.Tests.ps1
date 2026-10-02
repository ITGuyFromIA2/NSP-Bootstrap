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
