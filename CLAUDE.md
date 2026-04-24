# CLAUDE.md

## Project Purpose

This repository automates Microsoft Entra ID (Azure AD) configuration for Posit products. The scripts create OIDC app registrations and optionally SCIM provisioning apps via the Azure CLI and Microsoft Graph API, then output copy-pasteable Linux shell commands to configure the Posit product's server-side config files.

The goal is to reduce a multi-step, error-prone manual process in the Azure portal to a single interactive (or fully automated) script run.

## Supported Products

- **Posit Workbench** — OIDC + optional SCIM provisioning
- **Posit Connect** — OIDC only
- **Posit Package Manager** — OIDC only

SCIM is only supported for Workbench (it can be configured alongside OIDC or independently).

## Script Pair: Bash and PowerShell

Two functionally equivalent scripts exist:

- `posit-oidc-scim-entra-configuration.sh` — Bash 4+, requires `az` and `jq`
- `posit-oidc-scim-entra-configuration.ps1` — PowerShell 7.0+, requires `az` in PATH

Both scripts are served directly from this GitHub repo for one-liner Azure Cloud Shell usage. After each round of changes, commit and push to `main` so the Cloud Shell one-liners pick up the updates immediately.

## Shared Script Architecture

Both scripts follow the same logical flow and section ordering:

1. **Helper functions** — prompt input, yes/no normalization, name truncation, az CLI wrappers
2. **Pre-flight** — verify `az` login, get tenant ID and signed-in user ID
3. **Product selection** — interactive or via `PRODUCT` env var
4. **OIDC app registration** — create app via Graph API, add delegated permissions, create client secret, add ownership, create service principal, require user assignment, assign signed-in user
5. **SCIM provisioning** (Workbench only) — instantiate template, wait for SP, add ownership, wait for propagation, create sync job, save credentials
6. **Output emit functions** — named functions (`emit_workbench_commands` / `Emit-WorkbenchCommands`, etc.) that print product-specific Linux configuration commands
7. **Summary and dispatch** — print resource IDs, call the appropriate emit function

Every prompt has a corresponding environment variable. If the env var is set, the prompt is skipped. This enables fully non-interactive automation.

## Required Language-Specific Differences

These divergences exist because Bash and PowerShell handle things fundamentally differently. Do not try to unify them.

### JSON body construction and passing

- **Bash**: Uses `jq -n --arg` to build JSON safely, passes the string directly to `az rest --body`.
- **PowerShell**: Builds PowerShell hashtables, converts with `ConvertTo-Json -Depth 5 -Compress`, writes to a temp file, and passes via `az rest --body @tempfile`. The temp file approach is required because Windows command-line argument parsing mangles inline JSON with quotes and special characters.

### az CLI output flag

- **Bash**: Uses `-o json` / `-o tsv` / `-o none`.
- **PowerShell**: Must use `--output json` (long form). PowerShell interprets `-o` as ambiguous between `-OutVariable` and `-OutBuffer`.

### stderr handling

- **Bash**: `2>&1` with grep/conditional checks on combined output.
- **PowerShell**: `Invoke-Az` separates stderr from stdout using `ForEach-Object` with `[System.Management.Automation.ErrorRecord]` type checking. This prevents non-JSON az CLI warnings (like UNC path warnings) from contaminating `ConvertFrom-Json` parsing.

### Variable parameter name

- **PowerShell**: Az wrapper functions use `$AzArgs` not `$Args`. `$Args` is an automatic variable in PowerShell and cannot be used as a parameter name.

### Error state collection

- **Bash**: `print_collected_info()` reads environment variables on demand when the ERR trap fires.
- **PowerShell**: Proactively populates a `$script:State` hashtable throughout execution, dumps it in a `trap` block. This is more robust for partial failures where env vars might not be set yet.

## Intentional Structural Alignment

Both scripts are deliberately kept parallel in structure. When modifying one, make the equivalent change in the other. Key aligned patterns:

- **Named emit functions** for each product's configuration output (not inline switch blocks)
- **Dual input mode** on every parameter: env var takes precedence, interactive prompt as fallback
- **Yes/No normalization** accepts y/yes/n/no case-insensitively, normalizes to Yes/No
- **Idempotent ownership** — owner-add calls are wrapped in try/catch or `|| true` because they error if the owner already exists
- **10-second propagation delay** after adding SCIM ownership before creating sync jobs
- **60-second retry loop** (12 attempts x 5 seconds) waiting for SCIM service principal availability
- **Name truncation** to 120 characters for Entra ID display name limits

## Graph API Details

Key endpoints and their quirks:

- `POST /v1.0/applications` — creates the app registration. Returns `.id` (object ID) and `.appId` (client ID). These are different.
- `POST /v1.0/applications/{id}/addPassword` — creates a client secret. Returns `.secretText` (not `.password`). The secret is only available in this response.
- `PUT /v1.0/servicePrincipals/{id}/synchronization/secrets` — saves SCIM credentials. Body format is `{"value": [{key, value}]}` not `{"credentials": [...]}`.
- `POST /v1.0/applicationTemplates/8adf8e6e-67b2-4cf2-a259-e3dc5476c621/instantiate` — the non-gallery SCIM provisioning template ID is hardcoded.
- Ownership propagation is eventually consistent. The 10-second sleep after adding SCIM app ownership is required or the sync job creation returns `Unauthorized`.

## Product Configuration Output

The scripts output Linux shell commands using `cat >> file <<'DELIM'` heredoc format. The heredoc delimiters are single-quoted (`<<'RSERVER'`, `<<'GCFG'`, `<<'SECRET'`) so they appear literally in the output with baked-in values. This format means changing a config file path requires editing only one line.

Product-specific details:
- **Workbench**: Appends to `rserver.conf` (key=value format), creates `openid-client-secret` file (mode 0600). Redirect path: `/openid/callback`
- **Connect**: Uses `sed` to change `Provider = "password"` to `Provider = "oauth2"`, appends `[OAuth2]` section to gcfg. Redirect path: `/__login__/callback`
- **Package Manager**: Uses `sed` to uncomment/set `Address`, appends `[OpenIDConnect]` section to gcfg. Redirect path: `/__login__/callback`

## Testing Protocol

**After every change to either script, you must:**

1. Run the modified script with dummy env vars against a live Azure tenant
2. Test at least the product path you changed (preferably all three)
3. Verify the output commands are syntactically correct
4. **Clean up all Azure resources created during testing**

### Cleanup

```bash
# List test resources
az ad app list --filter "startswith(displayName, 'YOUR-TEST-PREFIX')" --query "[].{name:displayName, appId:appId}" -o table

# Delete by appId (also removes associated service principals and secrets)
az ad app delete --id <APP_ID>
```

Always use a distinctive prefix for test app names (e.g., `ps-test-`, `bash-test-`) so cleanup queries are targeted.

### Testing the PowerShell script from WSL

The PS1 script can be tested from WSL2 via the Windows pwsh:

```bash
PWSH="/mnt/c/Users/samco/AppData/Local/Microsoft/WindowsApps/Microsoft.PowerShell_8wekyb3d8bbwe/pwsh.exe"
"$PWSH" -NoProfile -Command '
$env:PATH += ";C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin"
$env:PRODUCT = "connect"
$env:APP_NAME = "test-connect-oidc"
$env:BASE_URL = "https://connect.test.example.com"
# ... other env vars ...
& "C:\Users\samco\posit-oidc-scim-entra-configuration.ps1"
'
```

Note: the `az` CLI path (`C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin`) is not in PATH when pwsh is invoked from WSL. The `$env:PATH +=` line is required. The PS1 file must be on the Windows filesystem (e.g., copy to `/mnt/c/Users/samco/` first) or accessed via UNC path.

## Files

- `posit-oidc-scim-entra-configuration.sh` — Bash script
- `posit-oidc-scim-entra-configuration.ps1` — PowerShell 7 script
- `default-configurations/` — Reference copies of default product config files (used during development testing)
- `test-run.log` — Historical test output; not maintained
- `README.md` — User-facing documentation
