# CLAUDE.md

## Project Purpose

This repository automates Microsoft Entra ID (Azure AD) configuration for Posit products. The scripts create OIDC or SAML app registrations, optionally configure SCIM provisioning apps via the Azure CLI and Microsoft Graph API, then output copy-pasteable Linux shell commands to configure the Posit product's server-side config files.

The goal is to reduce a multi-step, error-prone manual process in the Azure portal to a single interactive (or fully automated) script run.

## Supported Products and Protocols

| Product | OIDC | SAML | SCIM |
|---------|------|------|------|
| Posit Workbench | Yes | Yes | Yes (alongside OIDC, SAML, or standalone) |
| Posit Connect | Yes | Yes | No |
| Posit Package Manager | Yes | No | No |

SCIM is only supported for Workbench. Package Manager always uses OIDC (no protocol selection menu).

## Script Pair: Bash and PowerShell

Two functionally equivalent scripts exist:

- `posit-entra-auth.sh` — Bash 4+, requires `az`, `jq`, and `curl`
- `posit-entra-auth.ps1` — PowerShell 7.0+, requires `az` in PATH

Both scripts are served directly from this GitHub repo for one-liner Azure Cloud Shell usage. After each round of changes, commit and push to `main` so the Cloud Shell one-liners pick up the updates immediately.

## Shared Script Architecture

Both scripts follow the same logical flow and section ordering:

1. **Helper functions** — prompt input, URL validation, yes/no normalization, name truncation, az CLI wrappers
2. **Posit logo** — base64-encoded PNG and `set_app_logo`/`Set-AppLogo` function to brand app registrations via the Graph logo endpoint
3. **Pre-flight** — verify `az` login, get tenant ID, signed-in user ID, Graph SP ID, define SCIM template ID
4. **Product selection** — interactive menu or via `PRODUCT` env var (workbench/connect/packagemanager)
5. **Auth protocol selection** — OIDC or SAML (skipped for Package Manager which is always OIDC; skipped for SCIM-only mode)
6. **Workbench mode selection** — for Workbench only: auth+SCIM, auth-only, or SCIM-only (via `WB_MODE` env var or interactive)
7. **Common prompts** — app name, base URL, sign-in audience, group claims
8. **Protocol-specific prompts** — OIDC: redirect URI, client secret name; SAML: ACS URL computed automatically
9. **JIT provisioning prompt** — Workbench only, controls `user-provisioning-*` and group claim settings in output
10. **SCIM prompts (early collection for unified mode)** — SCIM URL, connectivity test, bearer token, start job, group provisioning
11. **App registration creation** — two paths: template instantiation (SAML or SCIM) vs direct `POST /applications` (OIDC-only)
12. **App logo** — set via direct Graph API PUT with access token
13. **OIDC-specific post-creation** — delegated permissions, client secret, admin consent grant
14. **Ownership and assignment** — add signed-in user as owner of both app registration and service principal, require user assignment, assign the signed-in user via appRoleAssignedTo
15. **SCIM provisioning** — standalone (mode 3) or unified (mode 1): create sync job, save credentials, optionally enable group mapping, optionally start job
16. **Output emit functions** — `emit_workbench_commands`, `emit_workbench_saml_commands`, `emit_connect_commands`, `emit_connect_saml_commands`, `emit_packagemanager_commands` (and PowerShell equivalents)
17. **Summary and dispatch** — print resource IDs, Azure portal links, call the appropriate emit function

Every prompt has a corresponding environment variable. If the env var is set, the prompt is skipped. This enables fully non-interactive automation.

## Environment Variables (All Prompts)

| Variable | Description | Used by |
|----------|-------------|---------|
| `PRODUCT` | Product selection: `workbench`/`connect`/`packagemanager` or `1`/`2`/`3` | All |
| `AUTH_PROTOCOL` | Auth protocol: `oidc`/`saml` or `1`/`2` | Workbench, Connect |
| `WB_MODE` | Workbench config mode: `oidc+scim`/`saml+scim`/`oidc`/`saml`/`scim` or `1`/`2`/`3` | Workbench |
| `APP_NAME` | App registration display name | All (when not SCIM-only) |
| `BASE_URL` | Product base URL (must start with `https://`) | All |
| `SIGNIN_AUDIENCE` | Sign-in audience: `AzureADMyOrg` or `AzureADMultipleOrgs` | All (when not SCIM-only) |
| `INCLUDE_GROUP_CLAIMS` | Include group claims: `Yes`/`No` | All (when not SCIM-only) |
| `GROUP_CLAIMS` | Group claim mode: `SecurityGroup`/`All`/`DirectoryRole`/`ApplicationGroup`/`None` | All (when not SCIM-only) |
| `REDIRECT_URI` | OIDC redirect URI (must end with product-specific suffix) | OIDC only |
| `CLIENT_SECRET_NAME` | Client secret display name | OIDC only |
| `ENABLE_JIT` | Enable JIT user provisioning: `Yes`/`No` | Workbench only |
| `SCIM_URL` | SCIM base URL (must end with `/scim/v2`) | SCIM modes |
| `SCIM_CONNECTIVITY_CONFIRMED` | Confirm SCIM connectivity if endpoint unreachable: `Yes`/`No` | SCIM modes |
| `SCIM_TOKEN` | SCIM bearer token (prompted as secret/password field) | SCIM modes |
| `START_SCIM` | Start SCIM sync job immediately: `Yes`/`No` | SCIM modes |
| `ENABLE_SCIM_GROUPS` | Enable SCIM group provisioning: `Yes`/`No` | SCIM modes |
| `SCIM_APP_NAME` | SCIM enterprise app name (SCIM-only mode) | SCIM-only mode |

## Auth Protocol Paths

### OIDC Path
- Creates app registration via `POST /v1.0/applications` with redirect URI, optional claims (email, preferred_username), implicit grant (ID token only), group membership claims
- Adds five delegated OpenID permissions (openid, profile, email, offline_access, User.Read)
- Creates client secret via `POST /applications/{id}/addPassword`
- Grants admin consent via `POST /oauth2PermissionGrants` (scope: `email offline_access openid profile User.Read`)

### SAML Path
- Creates enterprise app from non-gallery template (`POST /applicationTemplates/{id}/instantiate`)
- Configures app registration with `identifierUris` (entity ID = `api://{clientId}`), `redirectUris` (ACS URL), and `groupMembershipClaims` via PATCH
- Enables SAML SSO mode on service principal via `PATCH /servicePrincipals/{id}` with `preferredSingleSignOnMode: "saml"`
- Constructs federation metadata URL: `https://login.microsoftonline.com/{tenantId}/federationmetadata/2007-06/federationmetadata.xml?appid={clientId}`
- No client secret or admin consent needed

### OIDC+SCIM Unified Path
- Uses template instantiation (same as SAML) instead of direct app creation, since SCIM requires an enterprise app from a template
- Then configures OIDC settings on the template-created app via PATCH
- SCIM reuses the same service principal

## Workbench Modes (WB_MODE)

| Mode | WB_MODE values | SKIP_OIDC | CREATE_SCIM | Description |
|------|---------------|-----------|-------------|-------------|
| 1 | `oidc+scim`, `saml+scim`, `oidc-scim`, `saml-scim`, `1` | No | Yes | Auth + SCIM unified on same enterprise app |
| 2 | `oidc`, `saml`, `2` | No | Yes→No | Auth only, no SCIM |
| 3 | `scim`, `3` | Yes | Yes | SCIM provisioning only (standalone app) |

Note: When `WB_MODE=3`/`scim`, the auth protocol is set to `scim-only` and all auth-related prompts/creation are skipped.

## SCIM Provisioning Details

### Unified Mode (Mode 1: auth+SCIM)
- Reuses the service principal created during template instantiation for auth
- Collects SCIM prompts (URL, token, start, groups) early, alongside auth prompts
- Creates sync job on the same SP

### Standalone Mode (Mode 3: SCIM-only)
- Creates a separate enterprise app from the non-gallery template
- Uses truncated name with `-scim-provisioning` suffix
- Independently collects SCIM URL, token, start, group prompts

### SCIM Connectivity Test
- Tests SCIM URL reachability with `curl` (Bash) or `Invoke-WebRequest` (PowerShell)
- If unreachable, prompts user to confirm they have alternative connectivity (VPN, private endpoint)
- If user declines, SCIM provisioning is skipped (`CREATE_SCIM` set to `No`)

### SCIM Group Provisioning
- When `ENABLE_SCIM_GROUPS=Yes`, fetches the sync job schema, enables the `Group` object mapping, and PUTs the updated schema back
- Adds `group-provisioning-start-gid=1000` to the emitted Workbench config

### SCIM Job Lifecycle
1. Create sync job: `POST /servicePrincipals/{id}/synchronization/jobs` with `templateId: "scim"`
2. Save credentials: `PUT /servicePrincipals/{id}/synchronization/secrets` with BaseAddress and SecretToken
3. Enable group mapping (optional): GET schema, enable Group objectMapping, PUT schema
4. Start job (optional): `POST /servicePrincipals/{id}/synchronization/jobs/{jobId}/start`

## Application Logo

Both scripts embed a base64-encoded Posit logo PNG and set it on every app registration created. The logo is set via a direct `PUT /v1.0/applications/{id}/logo` call using a bearer token (not `az rest`), with `Content-Type: image/png`. Logo failure is non-fatal — logged as a warning.

## JIT (Just-In-Time) User Provisioning

Workbench-only feature. When enabled:

**OIDC output adds:**
- `user-provisioning-enabled=1`
- `user-provisioning-register-on-first-login=1`
- `auth-openid-groups-claim=groups` (only if group claims are included)

**SAML output adds:**
- `user-provisioning-enabled=1`
- `user-provisioning-register-on-first-login=1`
- `auth-saml-sp-attribute-groups=http://schemas.microsoft.com/ws/2008/06/identity/claims/groups` (only if group claims are included)

When SCIM is also enabled alongside JIT, `user-provisioning-enabled=1` is not duplicated (only emitted once).

## App Role Assignment

Both scripts:
1. Require user assignment on the enterprise app (`appRoleAssignmentRequired: true`)
2. Look up the first enabled app role on the service principal; if none exist, use the default role ID `00000000-0000-0000-0000-000000000000`
3. Assign the signed-in user to the enterprise app via `POST /servicePrincipals/{id}/appRoleAssignedTo`

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

### SCIM connectivity test

- **Bash**: `curl -sk --connect-timeout 10` — treats any response (including HTTP errors) as reachable.
- **PowerShell**: `Invoke-WebRequest -Method Head -TimeoutSec 10 -SkipCertificateCheck` — catches `HttpRequestException` as unreachable, treats all other exceptions (including HTTP errors) as reachable.

### PowerShell az wrapper hierarchy

Four wrapper functions in PowerShell:
- `Invoke-Az` — raw az call with stderr separation, returns string output
- `Invoke-AzJson` — adds `--output json`, joins output, pipes through `ConvertFrom-Json`
- `Invoke-AzRestJson` — `az rest` with temp-file body, returns parsed JSON
- `Invoke-AzRestVoid` — `az rest` with temp-file body, discards output

Bash has no wrappers; `az` and `az rest` are called inline with `jq` for parsing.

## Intentional Structural Alignment

Both scripts are deliberately kept parallel in structure. When modifying one, make the equivalent change in the other. Key aligned patterns:

- **Named emit functions** for each product/protocol combination (not inline switch blocks)
- **Dual input mode** on every parameter: env var takes precedence, interactive prompt as fallback
- **Yes/No normalization** accepts y/yes/n/no case-insensitively, normalizes to Yes/No
- **URL validation** requires `https://` prefix; redirect URIs and SCIM URLs also validate expected suffix
- **Idempotent ownership** — owner-add calls are wrapped in try/catch or `|| true` because they error if the owner already exists
- **App logo** set on every app registration (OIDC, SAML, SCIM standalone)
- **Two creation paths** — template instantiation (SAML, SCIM, OIDC+SCIM) vs direct POST (OIDC-only)
- **10-second propagation delay** after adding SCIM ownership before creating sync jobs
- **60-second retry loop** (12 attempts x 5 seconds) waiting for service principal availability after template instantiation
- **30-second retry loop** (6 attempts x 5 seconds) waiting for service principal when created directly via `az ad sp create`
- **Name truncation** to 120 characters for Entra ID display name limits

## Graph API Details

Key endpoints and their quirks:

- `POST /v1.0/applications` — creates the app registration. Returns `.id` (object ID) and `.appId` (client ID). These are different.
- `PATCH /v1.0/applications/{id}` — updates app properties. Used to configure SAML/OIDC settings on template-instantiated apps.
- `POST /v1.0/applications/{id}/addPassword` — creates a client secret. Returns `.secretText` (not `.password`). The secret is only available in this response.
- `PUT /v1.0/applications/{id}/logo` — sets the app logo. Requires bearer token auth directly (not via `az rest`), Content-Type `image/png`.
- `POST /v1.0/applicationTemplates/8adf8e6e-67b2-4cf2-a259-e3dc5476c621/instantiate` — the non-gallery SCIM provisioning template ID is hardcoded. Used for SAML, SCIM, and OIDC+SCIM paths.
- `PATCH /v1.0/servicePrincipals/{id}` — used to set `preferredSingleSignOnMode: "saml"` and `appRoleAssignmentRequired: true`.
- `POST /v1.0/servicePrincipals/{id}/appRoleAssignedTo` — assigns the signed-in user to the enterprise app.
- `POST /v1.0/oauth2PermissionGrants` — grants admin consent for delegated OIDC permissions.
- `PUT /v1.0/servicePrincipals/{id}/synchronization/secrets` — saves SCIM credentials. Body format is `{"value": [{key, value}]}` not `{"credentials": [...]}`.
- `GET/PUT /v1.0/servicePrincipals/{id}/synchronization/jobs/{jobId}/schema` — used to enable Group object mapping for SCIM group sync.
- Ownership propagation is eventually consistent. The 10-second sleep after adding SCIM app ownership is required or the sync job creation returns `Unauthorized`.

### OIDC Delegated Permission IDs

| Permission | GUID |
|------------|------|
| openid | `37f7f235-527c-4136-accd-4a02d197296e` |
| profile | `64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0` |
| email | `14dad69e-099b-42c9-810b-d002981feec1` |
| offline_access | `7427e0e9-2fba-42fe-b0c0-848c9e6a818b` |
| User.Read | `e1fe6dd8-ba31-4d61-89e7-88639da4683d` |

## Product Configuration Output

The scripts output Linux shell commands for server-side configuration.

### Workbench OIDC
- Appends to `/etc/rstudio/rserver.conf`: `auth-openid=1`, `auth-openid-issuer`, `auth-openid-username-claim=preferred_username`
- Optional JIT lines: `user-provisioning-enabled=1`, `user-provisioning-register-on-first-login=1`, `auth-openid-groups-claim=groups`
- Optional SCIM lines: `user-provisioning-enabled=1`, `group-provisioning-start-gid=1000`
- Encrypts client secret via `rstudio-server encrypt-password`
- Creates `/etc/rstudio/openid-client-secret` with `client-id` and `client-secret` (mode 0600)

### Workbench SAML
- Appends to `/etc/rstudio/rserver.conf`: `auth-saml=1`, `auth-saml-metadata-url`, `auth-saml-sp-name-id-format=emailaddress`, `auth-saml-sp-attribute-username=NameID`
- Optional JIT lines: `user-provisioning-enabled=1`, `user-provisioning-register-on-first-login=1`, `auth-saml-sp-attribute-groups=http://schemas.microsoft.com/ws/2008/06/identity/claims/groups`
- Optional SCIM lines: same as OIDC
- No client secret needed

### Connect OIDC
- `sed` changes `Provider = "password"` to `Provider = "oauth2"` in `/etc/rstudio-connect/rstudio-connect.gcfg`
- Encrypts client secret via `rscadmin encrypt-config-value`
- Appends `[OAuth2]` section with `ClientId`, `ClientSecret`, `OpenIDConnectIssuer`, `RequireUsernameClaim = true`, `UsernameClaim = "preferred_username"`
- Optional group lines: `GroupsAutoProvision = true`, `GroupsClaim = "groups"`

### Connect SAML
- `sed` changes `Provider = "password"` to `Provider = "saml"` in `/etc/rstudio-connect/rstudio-connect.gcfg`
- Appends `[SAML]` section with `IdPMetaDataURL`, `IdPAttributeProfile = azure`, `IdPSingleSignOnPostBinding = true`
- Optional group line: `GroupsAutoProvision = true`

### Package Manager OIDC
- `sed` uncomments/sets `Address` in `/etc/rstudio-pm/rstudio-pm.gcfg`
- Encrypts client secret via `/opt/rstudio-pm/bin/rspm encrypt`
- Appends `[OpenIDConnect]` section with `Issuer`, `ClientId`, `ClientSecret` (encrypted)

### SCIM-only (Workbench)
- Appends to `/etc/rstudio/rserver.conf`: `user-provisioning-enabled=1`
- Optional: `group-provisioning-start-gid=1000` (if SCIM group provisioning is enabled)

### Output Summary Section
All paths (except SCIM-only) print a summary block containing:
- Tenant ID, Client ID, Enterprise App SP ID
- OIDC: Client secret, Redirect URI, Issuer
- SAML: Entity ID, ACS URL, Metadata URL
- Azure portal links for both the App Registration and Enterprise App
- SCIM info (if applicable): job ID, SCIM URL, and for standalone mode also app/client ID, SP ID, and portal link

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
& "C:\Users\samco\posit-entra-auth.ps1"
'
```

Note: the `az` CLI path (`C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin`) is not in PATH when pwsh is invoked from WSL. The `$env:PATH +=` line is required. The PS1 file must be on the Windows filesystem (e.g., copy to `/mnt/c/Users/samco/` first) or accessed via UNC path.

## Files

- `posit-entra-auth.sh` — Bash script
- `posit-entra-auth.ps1` — PowerShell 7 script
- `default-configurations/` — Reference copies of default product config files (used during development testing)
- `test-run.log` — Historical test output; not maintained
- `README.md` — User-facing documentation
