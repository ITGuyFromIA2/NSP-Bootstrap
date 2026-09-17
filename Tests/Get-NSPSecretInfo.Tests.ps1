<#
    Pester 6. Covers the two portable sources (DPAPI file, environment variable) - the vault
    source needs the store initialised on the box and is covered manually per SECRETS.md, same
    convention as Get-NSPSecret.Tests.ps1.
#>

BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'NSP.Bootstrap.psd1') -Force -ErrorAction Stop
    $script:TestName = 'Pester.Bootstrap.InfoTestSecret'
    $script:EnvVar   = 'NSP_SECRET_PESTER_BOOTSTRAP_INFOTESTSECRET'
}

AfterAll {
    Remove-Item "Env:\$EnvVar" -ErrorAction SilentlyContinue
    Remove-NSPSecret -Name $TestName -Scope File -ErrorAction SilentlyContinue
    Remove-Module NSP.Bootstrap -Force -ErrorAction SilentlyContinue
}

Describe 'Get-NSPSecretInfo' {

    AfterEach { Remove-Item "Env:\$EnvVar" -ErrorAction SilentlyContinue }

    It 'never returns a Value property (names/metadata only)' {
        Set-Item "Env:\$EnvVar" -Value 'should-never-appear'
        $info = Get-NSPSecretInfo -Name 'Pester.Bootstrap.InfoTestSecret*'
        $info | Get-Member -Name Value -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        ($info | Out-String) | Should -Not -Match 'should-never-appear'
    }

    It 'lists an environment-sourced secret with Source EnvironmentVariable' {
        Set-Item "Env:\$EnvVar" -Value 'irrelevant'
        $info = Get-NSPSecretInfo -Name 'Pester.Bootstrap.InfoTestSecret*'
        $info | Where-Object Source -eq 'EnvironmentVariable' | Should -Not -BeNullOrEmpty
        ($info | Where-Object Source -eq 'EnvironmentVariable').Name | Should -Be $EnvVar
    }

    It 'lists a DPAPI-file-sourced secret with Source File' {
        Set-NSPSecret -Name $TestName -Secret (ConvertTo-SecureString 'irrelevant' -AsPlainText -Force) -Scope File
        $info = Get-NSPSecretInfo -Name $TestName
        $fileEntry = $info | Where-Object Source -eq 'File'
        $fileEntry.Name | Should -Be $TestName
    }

    It 'wildcard -Name narrows results' {
        Set-NSPSecret -Name $TestName -Secret (ConvertTo-SecureString 'irrelevant' -AsPlainText -Force) -Scope File
        # @() wrap is required, not stylistic: a bare (Get-NSPSecretInfo ...).Count is $null (not 0)
        # when the pipeline yields nothing, and can behave inconsistently at exactly one result too -
        # wrapping in @() forces a real array both times.
        @(Get-NSPSecretInfo -Name $TestName).Count | Should -BeGreaterOrEqual 1
        @(Get-NSPSecretInfo -Name 'Definitely.Not.A.Real.Prefix.*').Count | Should -Be 0
    }

    It 'defaults -Name to everything' {
        Set-NSPSecret -Name $TestName -Secret (ConvertTo-SecureString 'irrelevant' -AsPlainText -Force) -Scope File
        $all = Get-NSPSecretInfo
        ($all | Where-Object Name -eq $TestName) | Should -Not -BeNullOrEmpty
    }
}
