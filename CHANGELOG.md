# Changelog

All notable changes to NSP.Bootstrap are documented here. Versions follow
[SemVer](https://semver.org/). Starting at `0.x`: the API is small and deliberate but hasn't
had any use outside NSP yet - `0.x` says so honestly. `1.0.0` lands once that's no longer true.
Once at `1.0.0`: breaking changes bump major, new functions/parameters bump minor, fixes bump
patch.

## 0.1.4

- `Set-NSPSecret -Scope File` no longer reports success when the write fails. Folder creation and the
  write terminate on error, the file is replaced atomically (temp file, then move), and "Stored" is
  printed only after the file reads back and decrypts to the value given. Found by the 2026-10-02
  security review: an access-denied write used to be followed by the green "Stored" line.
- The loader dot-sources files in name order.

## 0.1.3

- `Test-NSPIsAdmin` - true when the session is elevated. One call site for the WindowsPrincipal
  check every self-elevating NSP script carried inline; `$false` (never throws) off Windows.
- `Invoke-NSPElevated` - relaunch a script (`-ScriptPath`) or a command (`-Command`, passed via
  `-EncodedCommand`) elevated, same PowerShell edition as the caller. Returns `$true` when it
  relaunched (caller exits), `$false` when already elevated (caller carries on). Lets
  module-hosted dashboards (NSP.ActiveDirectory, NSP.NPS, ...) self-elevate without a script path
  to re-run. Absorbs the `NSP.Elevation` candidate from the PoSHRepo reorg. Setting the
  environment variable `NSP_NO_ELEVATE=1` turns relaunching off for the session (a tool launcher
  run with `-NoElevate`, tests).

## 0.1.2

- `ConvertTo-NSPSubnetMask` - CIDR prefix length (0-32) -> dotted-decimal subnet mask. Adopted
  verbatim from NSP-FGTIPSecTools CLI Builder, the first consumer to take NSP.Bootstrap as a real
  module dependency rather than a hand-copied function.

## 0.1.1

- `Test-NSPSecret` - preflight for one named secret: is it readable right now, which source would
  win, and a specific failure reason if not (vault not registered / vault locked or unreachable /
  secret missing), without ever returning the value. Accepts pipeline input to check a whole
  credential set at startup.
- `Get-NSPSecret -Source` - pin resolution to exactly one of `EnvironmentVariable`, `Vault`, or
  `File` instead of walking the normal fallback chain; throws if that source doesn't have it, even
  if another source would. For a sensitive scheduled job that must not silently pick up an ambient
  environment-variable override.
- `Set-NSPSecret -NonInteractive` - throws instead of prompting when no `-Secret` was supplied.
  The interactive `Read-Host` prompt is still the default; this is for CI/scheduled use, where a
  prompt would just hang.
- Fixed: `Initialize-NSPSecretStore` no longer resets the SecretStore authentication mode on a
  routine rerun. It now only applies `-RequirePassword`/default mode on first-time setup (vault
  not yet registered) or when `-RequirePassword` is passed explicitly - previously a bare rerun
  (e.g. after a module update) would silently downgrade an already password-protected store back
  to no-password.
- Published on the PowerShell Gallery; README install instructions updated accordingly.

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
