# Changelog

All notable changes to NSP.Bootstrap are documented here. Versions follow
[SemVer](https://semver.org/). Starting at `0.x`: the API is small and deliberate but hasn't
had any use outside NSP yet - `0.x` says so honestly. `1.0.0` lands once that's no longer true.
Once at `1.0.0`: breaking changes bump major, new functions/parameters bump minor, fixes bump
patch.

## 0.1.0

First public release.

- `Get-NSPSecret` / `Set-NSPSecret` / `Remove-NSPSecret` - environment variable -> SecretManagement
  vault -> DPAPI fallback file resolution chain.
- `Get-NSPSecretInfo` - lists secret names and where they're stored (vault / DPAPI file /
  environment variable), never values.
- `Test-NSPSecretStore` - diagnostics: is SecretManagement/SecretStore installed, is the vault
  registered, is it actually reachable right now, how many DPAPI fallback entries exist.
- `Initialize-NSPSecretStore` - one-time SecretManagement + SecretStore setup.
- `Install-NSPModule` - PSGallery install helper, TLS 1.2 forced, no permanent gallery-trust
  changes.
- `New-NSPRandomPassword` - cross Windows PowerShell 5.1 / PowerShell 7+ password generator
  (`System.Security.Cryptography.RandomNumberGenerator`, not
  `[System.Web.Security.Membership]::GeneratePassword`, which is absent under 7+).
- Pester 5+ test suite, PSScriptAnalyzer-clean, no `RequiredModules` (imports on a bare Windows
  PowerShell 5.1 host).
