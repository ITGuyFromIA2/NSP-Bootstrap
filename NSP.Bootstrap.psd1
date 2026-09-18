@{
    RootModule        = 'NSP.Bootstrap.psm1'
    ModuleVersion     = '0.1.1'
    GUID              = '40ee65bf-0574-4797-8b4e-14230354b10b'
    Author            = 'Network Systems Plus'
    CompanyName       = 'Network Systems Plus'
    Copyright         = '(c) Network Systems Plus. All rights reserved.'
    Description       = 'Shared bootstrap layer for NSP PowerShell tooling: module install, secret storage, and small cross-version helpers. Windows PowerShell 5.1 compatible.'

    # 5.1 is the floor for every NSP toolkit. This module must import on a bare 5.1 host with
    # nothing else installed - so SecretManagement/SecretStore are NOT RequiredModules here; the
    # secret functions detect their absence and fall back or throw a clear instruction.
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Install-NSPModule'
        'Initialize-NSPSecretStore'
        'Get-NSPSecret'
        'Set-NSPSecret'
        'Remove-NSPSecret'
        'Get-NSPSecretInfo'
        'Test-NSPSecretStore'
        'Test-NSPSecret'
        'New-NSPRandomPassword'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('NSP', 'Bootstrap', 'Secret', 'SecretManagement', 'CredentialStore')
            ProjectUri   = 'https://github.com/ITGuyFromIA2/NSP-Bootstrap'
            LicenseUri   = 'https://github.com/ITGuyFromIA2/NSP-Bootstrap/blob/main/LICENSE'
            ReleaseNotes = 'https://github.com/ITGuyFromIA2/NSP-Bootstrap/blob/main/CHANGELOG.md'
        }
    }
}
