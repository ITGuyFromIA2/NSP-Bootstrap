<#
    Pester 5. Module hygiene: manifest is valid, module imports clean, every exported function
    has comment-based help with at least a synopsis and one example.

    Run:  Invoke-Pester -Path .\Tests
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $ModuleRoot 'NSP.Bootstrap.psd1'
    Import-Module $ManifestPath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module NSP.Bootstrap -Force -ErrorAction SilentlyContinue
}

Describe 'NSP.Bootstrap manifest' {

    It 'has a valid module manifest' {
        { Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'targets Windows PowerShell 5.1 as the floor' {
        (Test-ModuleManifest -Path $ManifestPath).PowerShellVersion | Should -Be ([version]'5.1')
    }

    It 'declares no RequiredModules (must import on a bare 5.1 host)' {
        (Test-ModuleManifest -Path $ManifestPath).RequiredModules.Count | Should -Be 0
    }

    It 'imports without error' {
        Get-Module NSP.Bootstrap | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly the functions listed in the manifest' {
        $manifestFns = (Import-PowerShellDataFile $ManifestPath).FunctionsToExport | Sort-Object
        $actualFns   = (Get-Command -Module NSP.Bootstrap -CommandType Function).Name | Sort-Object
        $actualFns | Should -Be $manifestFns
    }
}

Describe 'NSP.Bootstrap exported help' {

    $exported = (Get-Command -Module NSP.Bootstrap -CommandType Function).Name

    It '<_> has a synopsis' -ForEach $exported {
        (Get-Help $_ -ErrorAction SilentlyContinue).Synopsis.Trim() | Should -Not -BeNullOrEmpty
    }

    It '<_> has at least one example' -ForEach $exported {
        @((Get-Help $_ -ErrorAction SilentlyContinue).Examples.Example).Count | Should -BeGreaterThan 0
    }
}
