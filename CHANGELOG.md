# Changelog

All notable changes to NSP.Bootstrap are documented here. Versions follow
[SemVer](https://semver.org/): breaking changes bump major, new functions/parameters bump
minor, fixes bump patch.

## 1.0.0

First public release.

### Added
- `Get-NSPSecretInfo` - lists secret names and where they're stored (vault / DPAPI file /
  environment variable), never values.
- `Test-NSPSecretStore` - diagnostics: is SecretManagement/SecretStore installed, is the vault
  registered, is it actually reachable right now, how many DPAPI fallback entries exist.
- `LicenseUri` and `ReleaseNotes` in the module manifest.

### Since the internal 0.1.0 baseline
- `Get-NSPSecret` / `Set-NSPSecret` / `Remove-NSPSecret` - environment variable -> SecretManagement
  vault -> DPAPI fallback file resolution chain.
- `Initialize-NSPSecretStore` - one-time SecretManagement + SecretStore setup.
- `Install-NSPModule` - PSGallery install helper, TLS 1.2 forced, no permanent gallery-trust
  changes.
- `New-NSPRandomPassword` - cross Windows PowerShell 5.1 / PowerShell 7+ password generator
  (`System.Security.Cryptography.RandomNumberGenerator`, not
  `[System.Web.Security.Membership]::GeneratePassword`, which is absent under 7+).
- Pester 5 test suite, PSScriptAnalyzer-clean.
