<#
    Pester 5.
#>

BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'NSP.Bootstrap.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module NSP.Bootstrap -Force -ErrorAction SilentlyContinue
}

Describe 'New-NSPRandomPassword' {

    It 'honours -Length' {
        (New-NSPRandomPassword -Length 24).Length | Should -Be 24
    }

    It 'contains at least -MinSpecial special characters' {
        $pw = New-NSPRandomPassword -Length 20 -MinSpecial 6
        $specials = ($pw.ToCharArray() | Where-Object { '!@#$%^&*-_=+'.Contains($_) }).Count
        $specials | Should -BeGreaterOrEqual 6
    }

    It 'never emits quote, backtick, or space (CLI-safe)' {
        $pw = -join (1..50 | ForEach-Object { New-NSPRandomPassword -Length 32 })
        $pw | Should -Not -Match "[`"' `` ]"
    }

    It 'excludes look-alike characters 0 O 1 l I' {
        $pw = -join (1..50 | ForEach-Object { New-NSPRandomPassword -Length 32 })
        $pw | Should -Not -Match '[0O1lI]'
    }

    It 'produces a different value each call' {
        (New-NSPRandomPassword) | Should -Not -Be (New-NSPRandomPassword)
    }

    It 'throws when -MinSpecial exceeds -Length' {
        { New-NSPRandomPassword -Length 8 -MinSpecial 12 } | Should -Throw
    }
}
