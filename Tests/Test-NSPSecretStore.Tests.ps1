<#
    Pester 6. Test-NSPSecretStore reports on real machine state (is SecretManagement installed,
    is the vault registered), which isn't something to fake convincingly in a unit test without
    mocking half the SecretManagement surface. This checks the contract - shape, types, that it
    never throws regardless of what's actually installed/registered on the box running it - not
    specific values.
#>

BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'NSP.Bootstrap.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module NSP.Bootstrap -Force -ErrorAction SilentlyContinue
}

Describe 'Test-NSPSecretStore' {

    It 'does not throw' {
        { Test-NSPSecretStore } | Should -Not -Throw
    }

    It 'returns exactly one object' {
        @(Test-NSPSecretStore).Count | Should -Be 1
    }

    It 'has the documented shape' {
        $result = Test-NSPSecretStore
        $expected = 'SecretManagementInstalled', 'SecretStoreInstalled', 'VaultName', 'VaultRegistered',
                    'VaultBackend', 'VaultReachable', 'VaultError', 'DpapiFallbackDir', 'DpapiFallbackCount'
        $actual = $result.PSObject.Properties.Name
        foreach ($prop in $expected) { $actual | Should -Contain $prop }
    }

    It 'boolean fields are actually booleans' {
        $result = Test-NSPSecretStore
        $result.SecretManagementInstalled | Should -BeOfType [bool]
        $result.SecretStoreInstalled | Should -BeOfType [bool]
        $result.VaultRegistered | Should -BeOfType [bool]
        $result.VaultReachable | Should -BeOfType [bool]
    }

    It 'VaultReachable is false when VaultRegistered is false (can''t be reachable if not registered)' {
        $result = Test-NSPSecretStore -Vault 'Definitely-Not-A-Registered-Vault-Name'
        $result.VaultRegistered | Should -BeFalse
        $result.VaultReachable | Should -BeFalse
    }

    It 'DpapiFallbackCount is never negative' {
        (Test-NSPSecretStore).DpapiFallbackCount | Should -BeGreaterOrEqual 0
    }

    It 'respects -Vault' {
        (Test-NSPSecretStore -Vault 'SomeOtherVaultName').VaultName | Should -Be 'SomeOtherVaultName'
    }
}
