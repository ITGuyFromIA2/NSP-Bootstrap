# NSP secret storage

## The model

Scripts never read a credential from a literal or a plaintext file. They call:

```powershell
$key = Get-NSPSecret -Name 'CW.Control.ApiKey' -AsPlainText
```

`Get-NSPSecret` resolves, first hit wins:

1. **Env var** `NSP_SECRET_<NAME>` (name upper-cased, non-alphanumerics -> `_`). For CI and
   one-off overrides. Plaintext by nature.
2. **`NSP` SecretManagement vault** - encrypted at rest. Local `SecretStore` backend today;
   swap to **Azure Key Vault** later with zero script changes (it is just another registered
   vault named `NSP`).
3. **DPAPI fallback file** `%LOCALAPPDATA%\NSP\Secrets\<name>.sec` - `ConvertFrom-SecureString`
   output, decryptable only by the **same Windows user on the same machine**. Last resort for a
   box where you don't want the SecretManagement modules.

Naming convention: `Vendor.Product.Purpose`, e.g. `CW.Control.ApiKey`, `CW.Automate.TotpSeed`,
`CW.Automate.ClientId`.

---

## One-time setup (per workstation)

```powershell
Import-Module 'C:\GitRepo\NSP-Bootstrap\NSP.Bootstrap.psd1'
Initialize-NSPSecretStore
```

Default is **no-password, current-user** mode: the vault unlocks automatically for you on this
machine, no prompt. Tradeoff: any process running as your account can read it without a
challenge - fine for an interactive tech laptop. For a shared server or a service identity use
`Initialize-NSPSecretStore -RequirePassword`, or go straight to Key Vault (below).

---

## Runbook: the ScreenConnect / CW Control API key

Original incident (resolved): the key `067b74f3-...` was in **PoSHRepo git history** (3 files,
pushed to GitHub), compromised. Rotated, scrubbed from history (`git filter-repo`), and
`NSP-AutomateControl` now reads it exclusively through `Get-NSPSecret` with no plaintext-file
fallback. Kept below as the repeatable rotation procedure for next time.

1. **Regenerate it in Control** - the actual path, not "Security / API" (that menu doesn't
   exist in Control; confirmed live 2026-09):

   **Prerequisite:** the "RESTful API Manager" extension isn't installed by default - if it's
   not already in your Extensions list, install it first (Admin -> Extensions -> add/browse
   extensions). The Edit Settings screen below doesn't exist until it's installed.

   **Admin -> Extensions -> "RESTful API Manager" -> the `...` menu on that row -> Edit
   Settings**, then on `RESTfulAuthenticationSecret`: select **Custom**, generate a new long
   random string (or GUID) as the value, **Save Settings**. Same screen also has
   `RESTfulUserName` (cosmetic - the name attached to events this API creates) and
   `RESTfulAllowedOrigin` (optional Origin-header allowlist) - leave both alone for a routine
   rotation.

   The old value stops working the moment you save. Everything below stores the **new** one.

2. **Store the new key:**
   ```powershell
   Import-Module 'C:\GitRepo\NSP-Bootstrap\NSP.Bootstrap.psd1'
   Initialize-NSPSecretStore          # if not done already
   Set-NSPSecret -Name 'CW.Control.ApiKey'      # paste the new key at the prompt (no echo)
   ```

3. **Verify:**
   ```powershell
   Get-NSPSecret -Name 'CW.Control.ApiKey' -AsPlainText
   ```

4. **`NSP-AutomateControl` reads it straight from here, no fallback.**
   `ControlRestApi.ps1` calls `Get-NSPSecret -Name 'CW.Control.ApiKey' -AsPlainText`
   unconditionally - if the store doesn't have it, the script throws immediately with a
   `Set-NSPSecret` pointer rather than limping along on a stale value.

---

## CW Automate secrets (Connect-AutomateControl.ps1)

`NSP-AutomateControl\Connect-AutomateControl.ps1` reads every Automate credential straight
through `Get-NSPSecret`, no fallback - same as the Control key above. The original migration
bridge (`Get-ATSecret`, a legacy-OneDrive-file fallback) was removed once the migration was
actually done; carrying forward unused fallback complexity was pointless once nothing exercised
it. If any of these four aren't set yet, `ConnectAPIServers` throws immediately naming which one.

| Secret name | What |
|---|---|
| `CW.Automate.TotpSeed` | base32 MFA seed |
| `CW.Automate.ClientId` | Automate API client id |
| `CW.Automate.User` | Automate API username |
| `CW.Automate.Password` | Automate API password (stored as a SecureString) |

```powershell
Import-Module 'C:\GitRepo\NSP-Bootstrap\NSP.Bootstrap.psd1'
Set-NSPSecret -Name 'CW.Automate.TotpSeed'     # paste the base32 seed
Set-NSPSecret -Name 'CW.Automate.ClientId'     # paste the API client id
Set-NSPSecret -Name 'CW.Automate.User'         # paste the API username
Set-NSPSecret -Name 'CW.Automate.Password'     # paste the password (stored as a SecureString)
Get-NSPSecretInfo -Name 'CW.Automate.*'        # confirm all four are present (names only)
```

Then run `Start-NSPControlMenu.ps1` (option 1) to confirm the Automate connect still works.

---

## Runbook: publishing a module to the PowerShell Gallery

1. **Get an API key.** powershellgallery.com -> sign in -> Account Settings -> API Keys ->
   Create. Scope it: a glob like `NSP.*` (not "all packages") and a real expiration date, not
   "never" - a key that only signs for the packages you actually intend to publish is one less
   thing that matters if it ever leaks.

2. **Store it:**
   ```powershell
   Import-Module 'C:\GitRepo\NSP-Bootstrap\NSP.Bootstrap.psd1'
   Set-NSPSecret -Name 'MS.PSGallery.ApiKey'
   ```

3. **Publish:**
   ```powershell
   .\tools\Publish-ToGallery.ps1 -WhatIf    # stage + validate only, no network call
   .\tools\Publish-ToGallery.ps1            # the real thing
   ```
   Not a plain `Publish-Module -Path .` - `Publish-Module` requires the source folder's name to
   exactly match the module name, and this repo's folder (`NSP-Bootstrap`, matching the GitHub
   naming convention every NSP-* repo uses) doesn't match the module's actual identity
   (`NSP.Bootstrap`, dot). `Publish-ToGallery.ps1` stages a correctly-named copy of the
   user-facing files (not `Tests\`/`tools\`/dev-only files) in a temp directory and publishes
   from there.

4. **Versions are immutable once published** - once `0.1.0` is out, it can never be
   overwritten, only superseded. Bump `ModuleVersion` in the manifest before every publish, even
   a doc-only fix.

---

## Medium term: Azure Key Vault

For "one store, N techs, M client keys, rotation in one place, every read audited":

1. Create a Key Vault in the NSP tenant. Grant techs (or an Entra group) `Key Vault Secrets
   User`.
2. `Install-NSPModule -Name Az.KeyVault, Microsoft.PowerShell.SecretManagement`
3. Register it under the **same vault name** the scripts already use:
   ```powershell
   Register-SecretVault -Name 'NSP' -ModuleName Az.KeyVault -VaultParameters @{
       AZKVaultName = '<vault-name>'
       SubscriptionId = '<sub-id>'
   } -DefaultVault
   ```
4. `Get-NSPSecret` now pulls from Key Vault. No script changes.

Auth per machine: interactive `Connect-AzAccount` for tech-run scripts; a service principal
with a **certificate** (cert in the CNG user store, not a client secret on disk) for unattended
/ scheduled runs.

For unattended jobs that already use a gMSA (e.g. `NSP-ADPasswordAlerts`), keep that model -
DPAPI under the gMSA identity, or Key Vault via a managed identity.
