# Posit OIDC & SCIM Configuration for Microsoft Entra ID

Automates the creation of Microsoft Entra ID (Azure AD) app registrations and SCIM provisioning for Posit products. Available as both a Bash script (Linux/macOS) and a PowerShell 7 script (Windows).

## Supported Products

| Product | OIDC | SCIM | Config File(s) |
|---------|------|------|-----------------|
| Posit Workbench | Yes | Yes (optional) | `/etc/rstudio/rserver.conf`, `/etc/rstudio/openid-client-secret` |
| Posit Connect | Yes | No | `/etc/rstudio-connect/rstudio-connect.gcfg` |
| Posit Package Manager | Yes | No | `/etc/rstudio-pm/rstudio-pm.gcfg` |

SCIM provisioning is only supported for Posit Workbench. For Workbench, SCIM can be configured alongside OIDC or independently (skip OIDC, SCIM only).

## Prerequisites

### Bash (`posit-oidc-scim-entra-configuration.sh`)

- Bash 4+
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`) logged in with sufficient Entra ID permissions
- `jq`

### PowerShell (`posit-oidc-scim-entra-configuration.ps1`)

- PowerShell 7.0+
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`) in PATH and logged in

### Required Entra ID Permissions

The signed-in user must be able to:

- Create app registrations (`POST /applications`)
- Create service principals (`az ad sp create`)
- Add delegated API permissions (`az ad app permission add`)
- Create client secrets (`POST /applications/{id}/addPassword`)
- Manage ownership of applications and service principals
- For SCIM: instantiate application templates and create synchronization jobs

Typically this requires the **Application Administrator** or **Cloud Application Administrator** Entra ID role.

## Quick Start (Azure Cloud Shell)

Run directly from the Azure Cloud Shell without cloning the repo:

**Bash** (Cloud Shell default):
```bash
bash <(curl -sL https://raw.githubusercontent.com/samcofer/oidc-scim-entra-script/main/posit-oidc-scim-entra-configuration.sh)
```

**PowerShell** (Cloud Shell PowerShell mode):
```powershell
Invoke-Expression (Invoke-RestMethod https://raw.githubusercontent.com/samcofer/oidc-scim-entra-script/main/posit-oidc-scim-entra-configuration.ps1)
```

Azure Cloud Shell comes pre-authenticated with `az` and includes `jq`, so no additional setup is needed.

## Usage

### Interactive

Run the script and follow the prompts:

```bash
# Bash
./posit-oidc-scim-entra-configuration.sh

# PowerShell
pwsh ./posit-oidc-scim-entra-configuration.ps1
```

### Non-Interactive (Environment Variables)

Every prompt can be pre-filled via environment variables to support automation. If a variable is set, the corresponding prompt is skipped.

```bash
# Example: fully automated Connect setup
export PRODUCT=connect
export APP_NAME=posit-connect-oidc
export BASE_URL=https://connect.example.com
export REDIRECT_URI=https://connect.example.com/__login__/callback
export CLIENT_SECRET_NAME=posit-connect-oidc-secret
export SIGNIN_AUDIENCE=AzureADMyOrg
export INCLUDE_GROUP_CLAIMS=Yes
export GROUP_CLAIMS=SecurityGroup

./posit-oidc-scim-entra-configuration.sh
```

## Environment Variables

### General

| Variable | Description | Default |
|----------|-------------|---------|
| `PRODUCT` | Product to configure: `workbench`/`1`, `connect`/`2`, `packagemanager`/`ppm`/`3` | _(interactive prompt)_ |

### OIDC

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_NAME` | Display name for the Entra ID app registration | `posit-{product}-oidc` |
| `BASE_URL` | Public base URL of the Posit product | _(required)_ |
| `REDIRECT_URI` | OAuth2 redirect URI | `{BASE_URL}/openid/callback` (Workbench) or `{BASE_URL}/__login__/callback` (Connect/PPM) |
| `CLIENT_SECRET_NAME` | Display name for the client secret | `{APP_NAME}-secret` |
| `SIGNIN_AUDIENCE` | Sign-in audience | `AzureADMyOrg` |
| `INCLUDE_GROUP_CLAIMS` | Include group claims in tokens (`Yes`/`No`) | `Yes` |
| `GROUP_CLAIMS` | Group claim mode: `SecurityGroup`, `All`, `DirectoryRole`, `ApplicationGroup`, `None` | `SecurityGroup` |

### Workbench Mode

| Variable | Description | Default |
|----------|-------------|---------|
| `WB_MODE` | Workbench configuration mode: `oidc+scim`/`1`, `oidc`/`2`, `scim`/`3` | _(interactive menu)_ |

### SCIM (Workbench Only, when mode includes SCIM)

| Variable | Description | Default |
|----------|-------------|---------|
| `SCIM_APP_NAME` | Display name for the SCIM enterprise app | `{APP_NAME}-scim-provisioning` |
| `SCIM_URL` | Workbench SCIM endpoint URL | `{BASE_URL}/scim/v2` |
| `SCIM_TOKEN` | SCIM bearer token (prompted securely; not echoed) | _(required if SCIM enabled)_ |
| `SCIM_CONNECTIVITY_CONFIRMED` | Confirm Azure-to-Workbench connectivity exists via VPN/private endpoint (`Yes`/`No`) | `No` |
| `START_SCIM` | Start the SCIM provisioning job immediately (`Yes`/`No`) | `No` |

## What the Scripts Create

### OIDC App Registration

1. **App registration** in Entra ID with:
   - Display name, redirect URI, sign-in audience
   - `groupMembershipClaims` set per user choice
   - `web.implicitGrantSettings.enableIdTokenIssuance = true`
   - Optional claims: `email`, `preferred_username` on the ID token
2. **Delegated API permissions** on Microsoft Graph:
   - `openid`, `email`, `profile`, `offline_access`, `User.Read`
3. **Client secret** with a configurable display name
4. **Ownership** assigned to the signed-in user on both the app registration and its service principal
5. **User assignment required** enabled on the enterprise app (`appRoleAssignmentRequired = true`), restricting sign-in to explicitly assigned users
6. **Signed-in user assigned** to the enterprise app's default role, enabling their login immediately

### SCIM Enterprise App (Workbench Only)

1. **Enterprise application** instantiated from the non-gallery SCIM provisioning template (`8adf8e6e-67b2-4cf2-a259-e3dc5476c621`)
2. **Ownership** assigned to the signed-in user (with a 10-second propagation delay)
3. **Synchronization job** created with the `scim` template
4. **SCIM credentials** saved (endpoint URL + bearer token)
5. Optionally **starts** the provisioning job immediately

## Output

After creating the Entra ID resources, the script prints:

1. A summary of all created resource IDs (tenant, client, SP, SCIM job, etc.)
2. **Copy-pasteable shell commands** to configure the Posit product's configuration files on the Linux server

The output commands use `cat >> file <<'DELIM'` heredoc format so that if a configuration file is at a non-standard path, only a single line needs to change.

### Workbench Output

- Appends `auth-openid=1`, `auth-openid-issuer`, and `auth-openid-username-claim` to `/etc/rstudio/rserver.conf`
- Creates `/etc/rstudio/openid-client-secret` with `client-id` and `client-secret` (mode `0600`)
- Restarts via `sudo rstudio-server restart`

### Connect Output

- Changes `Provider = "password"` to `Provider = "oauth2"` in `/etc/rstudio-connect/rstudio-connect.gcfg`
- Appends an `[OAuth2]` section with `ClientId`, `ClientSecret`, `OpenIDConnectIssuer`, `RequireUsernameClaim`, `GroupsAutoProvision`, `UsernameClaim`, `GroupsClaim`
- Restarts via `sudo systemctl restart rstudio-connect`

### Package Manager Output

- Uncomments and sets the `Address` field in `/etc/rstudio-pm/rstudio-pm.gcfg`
- Appends an `[OpenIDConnect]` section with `Issuer`, `ClientId`, `ClientSecret`
- Restarts via `sudo systemctl restart rstudio-pm`

## Error Handling

Both scripts collect state as they progress. If the script fails at any point, a trap handler prints all collected information (tenant ID, client ID, SP IDs, etc.) to help with debugging or manual cleanup. Client secrets are masked in this output.

## Graph API Endpoints Used

| Operation | Method | Endpoint |
|-----------|--------|----------|
| Create app registration | POST | `/v1.0/applications` |
| Add client secret | POST | `/v1.0/applications/{id}/addPassword` |
| Add app/SP owner | POST | `/v1.0/applications/{id}/owners/$ref`, `/v1.0/servicePrincipals/{id}/owners/$ref` |
| Require user assignment | PATCH | `/v1.0/servicePrincipals/{id}` |
| Assign user to app | POST | `/v1.0/servicePrincipals/{id}/appRoleAssignedTo` |
| Instantiate SCIM template | POST | `/v1.0/applicationTemplates/{id}/instantiate` |
| Create sync job | POST | `/v1.0/servicePrincipals/{id}/synchronization/jobs` |
| Save SCIM secrets | PUT | `/v1.0/servicePrincipals/{id}/synchronization/secrets` |
| Start sync job | POST | `/v1.0/servicePrincipals/{id}/synchronization/jobs/{id}/start` |
| Add delegated permissions | `az ad app permission add` (CLI) | |
| Create service principal | `az ad sp create` (CLI) | |

## Script Conventions

### Shared Between Both Scripts

- **Dual input mode**: every parameter can be supplied interactively or via environment variable. If the env var is set, the prompt is skipped entirely.
- **Yes/No normalization**: accepts `y`, `yes`, `n`, `no` (case-insensitive) and normalizes to `Yes`/`No`.
- **Name truncation**: SCIM app names are truncated to stay within the 120-character Entra ID display name limit.
- **Idempotent ownership**: owner-add calls are wrapped in try/catch (or `|| true`) because they fail if the owner already exists.
- **Propagation delays**: a 10-second sleep after adding SCIM app ownership, and a retry loop (up to 60 seconds) waiting for the SCIM service principal to become queryable.

### Bash-Specific

- Uses `jq -n` with `--arg` for safe JSON body construction (no shell injection risk).
- Pipes `az rest` output through `jq -r` for field extraction.
- Functions (`prompt`, `yesno`, `truncate_name`, `select_product`) export variables directly.
- Error trap uses `ERR` signal and prints all collected state.

### PowerShell-Specific

- Requires PowerShell 7.0+ (`#Requires -Version 7.0`).
- Uses `ConvertTo-Json -Depth 5 -Compress` for JSON body construction.
- JSON bodies are written to temp files and passed via `@filename` to `az rest` to avoid Windows command-line argument escaping issues.
- Helper functions separate stderr from stdout when invoking `az` to prevent non-JSON error text from contaminating `ConvertFrom-Json` parsing.
- Uses `--output json` instead of `-o json` because PowerShell interprets `-o` as ambiguous (matches `-OutVariable` and `-OutBuffer`).
- Error state is collected in a `$script:State` hashtable and displayed via a `trap` block.

## Repository Structure

```
.
├── README.md
├── posit-oidc-scim-entra-configuration.sh    # Bash script (Linux/macOS)
├── posit-oidc-scim-entra-configuration.ps1   # PowerShell 7 script (Windows)
└── default-configurations/                    # Reference copies of default product config files
    ├── rserver.conf                           # Default Posit Workbench config
    └── rstudio-connect.gcfg                   # Default Posit Connect config
```

## Cleanup

To remove resources created by the script, delete the app registrations by their client (app) IDs:

```bash
az ad app delete --id <CLIENT_ID>
# If SCIM was created:
az ad app delete --id <SCIM_APP_ID>
```

Deleting an app registration automatically removes its associated service principal and client secrets.
