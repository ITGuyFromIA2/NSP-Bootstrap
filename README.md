# NSP.Bootstrap

Shared bootstrap layer for NSP PowerShell tooling. Windows PowerShell **5.1** compatible (and
7+). Toolkit #1 of the PoSHRepo reorg - every other NSP toolkit is expected to depend on this
one.

## What's in it

| Function | Purpose |
|---|---|
| `Install-NSPModule` | One function replacing the 6+ copies of the "trust gallery / Find-Module / Install-Module" block. TLS 1.2, CurrentUser scope, no permanent trust changes. |
| `Initialize-NSPSecretStore` | One-time setup of the local `NSP` secret vault (SecretManagement + SecretStore). No-password current-user mode by default; `-RequirePassword` for shared/server hosts. |
| `Get-NSPSecret` | Single retrieval call site. Resolution order: env var `NSP_SECRET_<NAME>` -> `NSP` vault -> DPAPI fallback file. Returns SecureString, or `-AsPlainText`. |
| `Set-NSPSecret` | Store/replace a secret. Prompts (no echo) if no value passed. `-Scope File` for the DPAPI fallback. |
| `Remove-NSPSecret` | Delete from vault, file, or both. |
| `New-NSPRandomPassword` | Cross-5.1/7 crypto-random password (adopted from NSP-FGTIPSecTools). CLI-safe charset, no look-alikes. |

## Install (dev / on a workstation)

Not published to a gallery. Put it on the module path so `Import-Module NSP.Bootstrap` works:

```powershell
# option A: symlink into the user module folder (admin, one time)
$dest = "$HOME\Documents\PowerShell\Modules\NSP.Bootstrap"          # 7+
# or  "$HOME\Documents\WindowsPowerShell\Modules\NSP.Bootstrap"     # 5.1
New-Item -ItemType SymbolicLink -Path $dest -Target 'C:\GitRepo\NSP-Bootstrap'

# option B: just import by path (what the NSP scripts currently do)
Import-Module 'C:\GitRepo\NSP-Bootstrap\NSP.Bootstrap.psd1'
```

## Secrets - start here

See **[SECRETS.md](SECRETS.md)** for the full model, the ScreenConnect / CW Control key
rotation runbook, and the Azure Key Vault path.

Quick version:

```powershell
Import-Module 'C:\GitRepo\NSP-Bootstrap\NSP.Bootstrap.psd1'
Initialize-NSPSecretStore
Set-NSPSecret -Name 'CW.Control.ApiKey'      # paste the NEW (rotated) key at the prompt
Get-NSPSecret -Name 'CW.Control.ApiKey' -AsPlainText
```

## Tests

```powershell
.\tools\Test-Repo.ps1            # PSScriptAnalyzer + Pester 5; prints install hint if deps missing
.\tools\Test-Repo.ps1 -InstallDeps
```

Module tests are Pester 5. The shared AST-extraction harness for testing functions embedded in
big side-effecting scripts lives in [`Tests/Shared/TestAssertions.ps1`](Tests/Shared/README.md)
- canonical copy, other repos reference it.
