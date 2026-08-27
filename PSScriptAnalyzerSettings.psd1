@{
    # NSP house lint config. Referenced by tools\Test-Repo.ps1 and by editor integrations.
    IncludeDefaultRules = $true
    Severity            = @('Error', 'Warning')

    ExcludeRules = @(
        # Set-NSPSecret intentionally accepts a plaintext value (tech-typed or read from a legacy
        # file during migration) and converts it to a SecureString for storage. The one call site
        # carries an inline SuppressMessageAttribute with justification.
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
}
