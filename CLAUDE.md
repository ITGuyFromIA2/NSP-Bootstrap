# CLAUDE.md

Guidance for Claude Code working in this repo.

## What this is

`NSP.Bootstrap` - the shared base module for NSP PowerShell tooling. Module install, secret
storage, small cross-version helpers. Toolkit #1 of the PoSHRepo reorg (see
`C:\GitRepo\PoSHRepo\ClaudeStuff\`).

## Hard rules

- **Windows PowerShell 5.1 is the floor.** No `??`, `?.`, ternary, `-Parallel`,
  `ConvertFrom-SecureString -AsPlainText`. If a helper needs a newer type, it must degrade or
  throw a clear message on 5.1, not error obscurely.
- **This module must import on a bare 5.1 host with nothing else installed.** SecretManagement /
  SecretStore / Pester / PSScriptAnalyzer are NOT `RequiredModules`. The secret functions detect
  their absence (`Get-Module -ListAvailable`) and fall back or instruct.
- One function per file: `Public\Verb-NSPNoun.ps1`, `Private\*.ps1`. `FunctionsToExport` in the
  manifest is the source of truth; the manifest test enforces it matches.
- Comment-based help on every exported function: `.SYNOPSIS` + at least one `.EXAMPLE`. Enforced
  by `Tests\NSP.Bootstrap.Manifest.Tests.ps1`.
- CRLF line endings (`.gitattributes`).

## Testing

- Module tests are **Pester 5** (`Describe`/`It`/`Should -Be`). Run `.\tools\Test-Repo.ps1`
  (PSScriptAnalyzer + Pester, non-zero exit on failure).
- `Tests\Shared\TestAssertions.ps1` is the **canonical copy** of the NSP AST-extraction test
  harness (for testing functions embedded in large side-effecting scripts elsewhere). Other
  repos copy it from here. Change it here, re-copy outward - don't fork it per repo.
- Only Pester 3.4.0 ships in-box; `Test-Repo.ps1 -InstallDeps` installs Pester 5 +
  PSScriptAnalyzer for the current user.

## Secrets

See `SECRETS.md`. Never put a credential in a literal, a committed file, or an example. The
`New-NSPRandomPassword` output and any test secret values are fine (they're not real).
