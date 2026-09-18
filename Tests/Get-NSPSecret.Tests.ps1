<#
    Pester 5. Covers the two resolution paths that need no external vault:
      - environment variable override
      - DPAPI fallback file round-trip (Set-NSPSecret -Scope File -> Get-NSPSecret)
    and the not-found error.

    The SecretManagement vault path is not exercised here (it needs the store initialised on the
    box); it is covered manually per SECRETS.md.
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

Describe 'Get-NSPSecret - environment override' {

    AfterEach { Remove-Item "Env:\$EnvVar" -ErrorAction SilentlyContinue }

    It 'resolves from NSP_SECRET_<NAME> and returns a SecureString by default' {
        Set-Item "Env:\$EnvVar" -Value 'env-value-123'
        $result = Get-NSPSecret -Name $TestName
        $result | Should -BeOfType [System.Security.SecureString]
    }

    It 'returns the plaintext with -AsPlainText' {
        Set-Item "Env:\$EnvVar" -Value 'env-value-123'
        Get-NSPSecret -Name $TestName -AsPlainText | Should -Be 'env-value-123'
    }

    It 'maps dots and dashes in the name to underscores for the env var' {
        Set-Item 'Env:\NSP_SECRET_CW_CONTROL_APIKEY' -Value 'abc'
        try {
            Get-NSPSecret -Name 'CW.Control.ApiKey' -AsPlainText | Should -Be 'abc'
        } finally {
            Remove-Item 'Env:\NSP_SECRET_CW_CONTROL_APIKEY' -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-NSPSecret - DPAPI fallback file' {

    It 'round-trips a value written by Set-NSPSecret -Scope File' {
        $secure = ConvertTo-SecureString -String 'file-value-xyz' -AsPlainText -Force
        Set-NSPSecret -Name $TestName -Secret $secure -Scope File
        Get-NSPSecret -Name $TestName -AsPlainText | Should -Be 'file-value-xyz'
    }

    It 'env var wins over the file when both exist' {
        Set-Item "Env:\$EnvVar" -Value 'env-wins'
        try {
            Get-NSPSecret -Name $TestName -AsPlainText | Should -Be 'env-wins'
        } finally {
            Remove-Item "Env:\$EnvVar" -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-NSPSecret - not found' {

    It 'throws an actionable error naming Set-NSPSecret' {
        { Get-NSPSecret -Name 'Definitely.Not.Stored.Anywhere.12345' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*Set-NSPSecret*'
    }
}

Describe 'Get-NSPSecret -Source' {

    AfterEach { Remove-Item "Env:\$EnvVar" -ErrorAction SilentlyContinue }

    It '-Source EnvironmentVariable resolves from the env var' {
        Set-Item "Env:\$EnvVar" -Value 'env-value-123'
        Get-NSPSecret -Name $TestName -Source EnvironmentVariable -AsPlainText | Should -Be 'env-value-123'
    }

    It '-Source EnvironmentVariable throws (not falls through to the file) when the env var is unset' {
        $secure = ConvertTo-SecureString -String 'file-value-xyz' -AsPlainText -Force
        Set-NSPSecret -Name $TestName -Secret $secure -Scope File
        try {
            { Get-NSPSecret -Name $TestName -Source EnvironmentVariable -ErrorAction Stop } |
                Should -Throw -ExpectedMessage "*EnvironmentVariable*"
        } finally {
            Remove-NSPSecret -Name $TestName -Scope File -ErrorAction SilentlyContinue
        }
    }

    It '-Source File resolves from the DPAPI file even when an env var is also set' {
        $secure = ConvertTo-SecureString -String 'file-value-xyz' -AsPlainText -Force
        Set-NSPSecret -Name $TestName -Secret $secure -Scope File
        Set-Item "Env:\$EnvVar" -Value 'env-would-otherwise-win'
        try {
            Get-NSPSecret -Name $TestName -Source File -AsPlainText | Should -Be 'file-value-xyz'
        } finally {
            Remove-NSPSecret -Name $TestName -Scope File -ErrorAction SilentlyContinue
        }
    }

    It '-Source File throws (not falls through to env) when no file exists' {
        Set-Item "Env:\$EnvVar" -Value 'env-would-otherwise-win'
        { Get-NSPSecret -Name $TestName -Source File -ErrorAction Stop } |
            Should -Throw -ExpectedMessage "*File*"
    }
}
