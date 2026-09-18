<#
    Pester 5. Same scope limit as Get-NSPSecret.Tests.ps1: only the sources that don't need a
    live SecretManagement vault initialised on the box are exercised here (env var, DPAPI file,
    and the true not-found case). The vault path - including "vault locked" vs "vault not
    registered" vs "not present in vault" - is covered manually per SECRETS.md.
#>

BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'NSP.Bootstrap.psd1') -Force -ErrorAction Stop
    $script:TestName = 'Pester.Bootstrap.TestSecret'
    $script:EnvVar   = 'NSP_SECRET_PESTER_BOOTSTRAP_TESTSECRET'
}

AfterAll {
    Remove-Item "Env:\$EnvVar" -ErrorAction SilentlyContinue
    Remove-NSPSecret -Name $TestName -Scope File -ErrorAction SilentlyContinue
    Remove-Module NSP.Bootstrap -Force -ErrorAction SilentlyContinue
}

Describe 'Test-NSPSecret' {

    AfterEach {
        Remove-Item "Env:\$EnvVar" -ErrorAction SilentlyContinue
        Remove-NSPSecret -Name $TestName -Scope File -ErrorAction SilentlyContinue
    }

    It 'never throws' {
        { Test-NSPSecret -Name $TestName } | Should -Not -Throw
    }

    It 'reports Available = $true, Source = EnvironmentVariable, and no Reason when the env var is set' {
        Set-Item "Env:\$EnvVar" -Value 'env-value-123'
        $result = Test-NSPSecret -Name $TestName
        $result.Available | Should -BeTrue
        $result.Source | Should -Be 'EnvironmentVariable'
        $result.Reason | Should -BeNullOrEmpty
    }

    It 'reports Available = $true, Source = File for a DPAPI fallback entry' {
        $secure = ConvertTo-SecureString -String 'file-value-xyz' -AsPlainText -Force
        Set-NSPSecret -Name $TestName -Secret $secure -Scope File
        $result = Test-NSPSecret -Name $TestName
        $result.Available | Should -BeTrue
        $result.Source | Should -Be 'File'
    }

    It 'env var wins over the file when both exist' {
        $secure = ConvertTo-SecureString -String 'file-value-xyz' -AsPlainText -Force
        Set-NSPSecret -Name $TestName -Secret $secure -Scope File
        Set-Item "Env:\$EnvVar" -Value 'env-wins'
        (Test-NSPSecret -Name $TestName).Source | Should -Be 'EnvironmentVariable'
    }

    It 'reports Available = $false with a non-empty Reason when nothing matches' {
        $result = Test-NSPSecret -Name 'Definitely.Not.Stored.Anywhere.98765'
        $result.Available | Should -BeFalse
        $result.Source | Should -Be 'None'
        $result.Reason | Should -Not -BeNullOrEmpty
    }

    It 'never returns the value itself - only Name/Available/Source/Detail/Reason' {
        Set-Item "Env:\$EnvVar" -Value 'must-not-leak'
        $result = Test-NSPSecret -Name $TestName
        $props = $result.PSObject.Properties.Name
        $props | Should -Be @('Name', 'Available', 'Source', 'Detail', 'Reason')
        ($result.PSObject.Properties.Value -join ' ') | Should -Not -Match 'must-not-leak'
    }

    It 'accepts multiple names via the pipeline' {
        Set-Item "Env:\$EnvVar" -Value 'env-value-123'
        $results = @('Definitely.Not.Stored.Anywhere.98765', $TestName) | Test-NSPSecret
        $results.Count | Should -Be 2
        ($results | Where-Object Name -EQ $TestName).Available | Should -BeTrue
        ($results | Where-Object Name -EQ 'Definitely.Not.Stored.Anywhere.98765').Available | Should -BeFalse
    }
}
