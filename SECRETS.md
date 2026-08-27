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

The key `067b74f3-...` is in **PoSHRepo git history** (3 files, pushed to GitHub). It is
compromised. No storage change fixes that - it has to be rotated.

1. **Rotate it in Control.** ScreenConnect Control -> Admin -> Security / API, regenerate the
   API key (or the API user's key). Invalidate the old value. Everything below stores the
   **new** key.

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

4. **`NSP-AutomateControl` already reads from here.** `Rework-RestfulAPI_Functional.ps1` now
   does `Get-NSPSecret -Name 'CW.Control.ApiKey'` and only falls back to the old
   `APIStuff\CL_CTRLAuthHeader.txt` (with a warning) if the secret store has nothing.

5. **Once step 3 works, delete the plaintext file:**
   ```powershell
   Remove-Item 'C:\GitRepo\NSP-AutomateControl\APIStuff\CL_CTRLAuthHeader.txt'
   ```
   (It is gitignored, so it was never committed in *that* repo - but it is a live plaintext
   key on disk and in OneDrive sync. Remove it.)

6. **Optional history scrub of PoSHRepo.** Rotating in step 1 is the real fix. If you also want
   the string gone from history: `git filter-repo --replace-text` on a fresh clone, force-push,
   everyone re-clones. Disruptive; schedule it, don't rush it.

---

## CW Automate secrets (Connect-NSP-ATControl.ps1)

`NSP-AutomateControl\Connect-NSP-ATControl.ps1` is now wired the same way: a local `Get-ATSecret`
helper reads from the NSP store and warns-and-falls-back to the legacy **OneDrive-synced**
`APIStuff\` plaintext file during migration.

| Legacy file | Secret name | Notes |
|---|---|---|
| `AT_Seed.txt` | `CW.Automate.TotpSeed` | **plaintext base32 TOTP seed in OneDrive - migrate first** |
| `ClientID.txt` | `CW.Automate.ClientId` | API client id |
| `AT_User.txt` | `CW.Automate.User` | API username (plaintext) |
| `AT_Pass.txt` | `CW.Automate.Password` | already DPAPI-encrypted; `Get-ATSecret -AsSecureString` reads the legacy file as a DPAPI blob, or the vault as a SecureString |

All four are wired via the `Get-ATSecret` helper in `Connect-NSP-ATControl.ps1` (warn +
fall back to the legacy file until the secret is stored).

```powershell
Import-Module 'C:\GitRepo\NSP-Bootstrap\NSP.Bootstrap.psd1'
Set-NSPSecret -Name 'CW.Automate.TotpSeed'     # paste the base32 seed
Set-NSPSecret -Name 'CW.Automate.ClientId'     # paste the API client id
Set-NSPSecret -Name 'CW.Automate.User'         # paste the API username
Set-NSPSecret -Name 'CW.Automate.Password'     # paste the password (stored as a SecureString)
Get-NSPSecret -Name 'CW.Automate.TotpSeed' -AsPlainText   # spot-check
```

Then run `Connect-NSP-ATControl.ps1` once to confirm the Automate connect still works, and
delete all four legacy files from the OneDrive `APIStuff\` folder (the runtime `BaseDir` in
`Connect-NSP-ATControl.ps1`, not the repo copy).

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
