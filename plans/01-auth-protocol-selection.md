# Step 1: Auth Protocol Selection

## What Changes
Add a new prompt after product selection (and before the Workbench mode selection) that asks which auth protocol to use: OIDC or SAML. PPM is OIDC-only so this prompt only appears for Connect and Workbench.

## New Env Var
- `AUTH_PROTOCOL` — accepts `oidc`, `saml`, `1`, `2`. Default: not set (interactive prompt).

## Flow Changes

### Product Selection (existing)
```
1) Posit Workbench
2) Posit Connect
3) Posit Package Manager
```

### NEW: Auth Protocol Selection (Connect + Workbench only)
```
Select authentication protocol:
  1) OpenID Connect (OIDC)
  2) SAML
```

- PPM: `AUTH_PROTOCOL` is forced to `oidc`, no prompt shown
- Workbench/Connect: prompt unless `AUTH_PROTOCOL` env var is set

### Impact on Existing Variables
- `SKIP_OIDC` is renamed conceptually to `SKIP_AUTH` (or we keep it as-is and just use `AUTH_PROTOCOL` to branch)
- Actually, simpler: keep the existing `SKIP_OIDC`/`SKIP_AUTH` variable as `SKIP_AUTH` and introduce `AUTH_PROTOCOL`. The `SKIP_AUTH` variable is only relevant for Workbench mode 3 (SCIM-only).

### Variable Naming Decision
Keep `SKIP_OIDC` as-is (it's internal, not user-facing). It means "skip auth app creation" — still accurate for SAML since SCIM-only mode skips both OIDC and SAML app creation.

### Default App Names
Change based on protocol:
- `posit-workbench-oidc` → `posit-workbench-saml` when SAML
- `posit-connect-oidc` → `posit-connect-saml` when SAML
- PPM stays `posit-package-manager-oidc`

### Workbench Mode Menu Update
When `AUTH_PROTOCOL=saml`, the Workbench mode menu becomes:
```
Select Workbench configuration mode:
  1) SAML + SCIM provisioning
  2) SAML only
  3) SCIM provisioning only
```
(Same structure, just label change from "OIDC" to "SAML")

Env var `WB_MODE` values should also accept `saml+scim`, `saml` alongside existing `oidc+scim`, `oidc`:
- `1|oidc-scim|oidc+scim|saml+scim|saml-scim` → mode 1
- `2|oidc|saml` → mode 2 (auth-only, protocol determined by AUTH_PROTOCOL)
- `3|scim` → mode 3

## Bash Implementation Points

### After `select_product` (line ~217), before the `case "$PRODUCT"` block:

```bash
# --- Auth protocol selection ---
if [[ "$PRODUCT" == "packagemanager" ]]; then
  AUTH_PROTOCOL="oidc"
else
  if [[ -n "${AUTH_PROTOCOL:-}" ]]; then
    case "${AUTH_PROTOCOL,,}" in
      1|oidc) AUTH_PROTOCOL="oidc" ;;
      2|saml) AUTH_PROTOCOL="saml" ;;
      *) echo "Invalid AUTH_PROTOCOL value: $AUTH_PROTOCOL. Use oidc or saml."; exit 1 ;;
    esac
  else
    echo ""
    echo "Select authentication protocol:"
    echo "  1) OpenID Connect (OIDC)"
    echo "  2) SAML"
    echo ""
    local choice
    while true; do
      read -rp "Protocol [1/2]: " choice </dev/tty
      echo
      case "$choice" in
        1|oidc) AUTH_PROTOCOL="oidc"; break ;;
        2|saml) AUTH_PROTOCOL="saml"; break ;;
        *) echo "Please enter 1 or 2." ;;
      esac
    done
  fi
  export AUTH_PROTOCOL
fi
```

### Update `DEFAULT_APP_NAME` to reflect protocol:
```bash
case "$PRODUCT" in
  workbench)
    DEFAULT_APP_NAME="posit-workbench-${AUTH_PROTOCOL}"
    ...
  connect)
    DEFAULT_APP_NAME="posit-connect-${AUTH_PROTOCOL}"
    ...
```

### Update `print_collected_info` to show AUTH_PROTOCOL:
Add `Auth protocol:         ${AUTH_PROTOCOL:-}` line.
