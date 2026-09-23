<#
    Pester 5.
#>

BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'NSP.Bootstrap.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module NSP.Bootstrap -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-NSPSubnetMask' {

    It 'converts <CIDR> to <Expected>' -ForEach @(
        @{ CIDR = 0;  Expected = '0.0.0.0' }
        @{ CIDR = 8;  Expected = '255.0.0.0' }
        @{ CIDR = 16; Expected = '255.255.0.0' }
        @{ CIDR = 24; Expected = '255.255.255.0' }
        @{ CIDR = 32; Expected = '255.255.255.255' }
        @{ CIDR = 30; Expected = '255.255.255.252' }
        @{ CIDR = 25; Expected = '255.255.255.128' }
        @{ CIDR = 12; Expected = '255.240.0.0' }
        @{ CIDR = 1;  Expected = '128.0.0.0' }
    ) {
        ConvertTo-NSPSubnetMask -CIDR $CIDR | Should -Be $Expected
    }

    It 'accepts CIDR positionally' {
        ConvertTo-NSPSubnetMask 24 | Should -Be '255.255.255.0'
    }

    It 'throws outside the 0-32 range' {
        { ConvertTo-NSPSubnetMask -CIDR 33 } | Should -Throw
        { ConvertTo-NSPSubnetMask -CIDR -1 } | Should -Throw
    }
}
