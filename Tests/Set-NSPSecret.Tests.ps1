<#
    Pester 5. Covers the -Scope File path (no live vault needed) and -NonInteractive, which is
    the part that's easy to get wrong (a missed check here means CI hangs on a Read-Host prompt
    instead of failing fast).
#>

BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'NSP.Bootstrap.psd1') -Force -ErrorAction Stop
    $script:TestName = 'Pester.Bootstrap.SetSecretTestSecret'
}

AfterAll {
    Remove-NSPSecret -Name $TestName -Scope File -ErrorAction SilentlyContinue
    Remove-Module NSP.Bootstrap -Force -ErrorAction SilentlyContinue
}

Describe 'Set-NSPSecret -Scope File' {

    AfterEach { Remove-NSPSecret -Name $TestName -Scope File -ErrorAction SilentlyContinue }

    It 'stores a [string] value' {
        Set-NSPSecret -Name $TestName -Secret 'plain-value' -Scope File
        Get-NSPSecret -Name $TestName -AsPlainText | Should -Be 'plain-value'
    }

    It 'stores a [SecureString] value' {
        $secure = ConvertTo-SecureString -String 'secure-value' -AsPlainText -Force
        Set-NSPSecret -Name $TestName -Secret $secure -Scope File
        Get-NSPSecret -Name $TestName -AsPlainText | Should -Be 'secure-value'
    }

    It 'throws on an empty string rather than storing nothing' {
        { Set-NSPSecret -Name $TestName -Secret '' -Scope File -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Set-NSPSecret -NonInteractive' {

    It 'throws instead of prompting when -Secret is omitted' {
        { Set-NSPSecret -Name $TestName -NonInteractive -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*NonInteractive*'
    }

    It 'does not throw when -Secret is supplied alongside -NonInteractive' {
        { Set-NSPSecret -Name $TestName -Secret 'ci-value' -Scope File -NonInteractive -ErrorAction Stop } |
            Should -Not -Throw
        Get-NSPSecret -Name $TestName -AsPlainText | Should -Be 'ci-value'
        Remove-NSPSecret -Name $TestName -Scope File -ErrorAction SilentlyContinue
    }
}
