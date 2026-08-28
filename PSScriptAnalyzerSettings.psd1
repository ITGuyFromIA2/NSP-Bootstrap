@{
    # NSP house lint config. Referenced by tools\Test-Repo.ps1 and by editor integrations.
    IncludeDefaultRules = $true
    Severity            = @('Error', 'Warning')

    ExcludeRules = @(
        # Set-NSPSecret intentionally accepts a plaintext value (tech-typed or read from a legacy
        # file during migration) and converts it to a SecureString for storage. The call site also
        # carries an inline SuppressMessageAttribute with justification.
        'PSAvoidUsingConvertToSecureStringWithPlainText'

        # This module is console/bootstrap tooling - Initialize-NSPSecretStore, Set-NSPSecret,
        # Test-Repo.ps1 and the shared test harness all use Write-Host deliberately for coloured
        # interactive status output, not as an accidental substitute for the pipeline.
        'PSAvoidUsingWriteHost'

        # New-NSPRandomPassword and the Reset-TestCounters test helper trip the "New-/Reset- verb
        # implies state change" heuristic but change nothing. The functions that genuinely change
        # state (Install-NSPModule, Initialize-NSPSecretStore, Set-/Remove-NSPSecret) all declare
        # SupportsShouldProcess.
        'PSUseShouldProcessForStateChangingFunctions'

        # Fires on the shared test harness (Assert-Contains, Reset-TestCounters, Test-ScriptParses).
        # That file is a canonical copy synced from NSP-FGTIPSecTools - not edited per-repo.
        'PSUseSingularNouns'
    )
}
