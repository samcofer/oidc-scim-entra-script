# Step 3: SAML Configuration Output Functions

## What Changes
Add new emit functions for SAML config output: `emit_workbench_saml_commands` and `emit_connect_saml_commands`. The output dispatch section branches on `AUTH_PROTOCOL`.

## Computed Values Available at Emit Time
- `TENANT_ID`
- `CLIENT_ID` (appId of the enterprise app)
- `BASE_URL`
- `SAML_METADATA_URL` = `https://login.microsoftonline.com/$TENANT_ID/federationmetadata/2007-06/federationmetadata.xml?appid=$CLIENT_ID`
- `SP_OBJECT_ID`
- `INCLUDE_GROUP_CLAIMS` / `GROUP_CLAIMS`

Note: SAML does NOT produce a client secret, so there's no `CLIENT_SECRET` variable.

## Connect SAML Output (`emit_connect_saml_commands`)

```bash
emit_connect_saml_commands() {
  local groups_line=""
  if [[ "$INCLUDE_GROUP_CLAIMS" == "Yes" ]]; then
    groups_line=$'\nGroupsAutoProvision = true'
  fi

  cat <<EOF
# Set auth provider to saml
sudo sed -i 's/^Provider = "password"/Provider = "saml"/' /etc/rstudio-connect/rstudio-connect.gcfg

# Append SAML settings
cat >> /etc/rstudio-connect/rstudio-connect.gcfg <<'GCFG'

[SAML]
IdPMetaDataURL = "$SAML_METADATA_URL"
IdPAttributeProfile = azure
IdPSingleSignOnPostBinding = true${groups_line}
GCFG

# Restart Connect
sudo systemctl restart rstudio-connect
EOF
}
```

Key details from kapa research:
- `IdPAttributeProfile = azure` auto-maps username, email, groups attributes
- `IdPSingleSignOnPostBinding = true` required for Entra ID
- `GroupsAutoProvision = true` only if groups enabled
- `Server.Address` must already be set (we assume it is, or add a sed for it)
- No client secret needed in config

## Workbench SAML Output (`emit_workbench_saml_commands`)

```bash
emit_workbench_saml_commands() {
  local jit_lines=""
  if [[ "${ENABLE_JIT:-}" == "Yes" ]]; then
    jit_lines=$'\nuser-provisioning-enabled=1\nuser-provisioning-register-on-first-login=1'
    if [[ "${INCLUDE_GROUP_CLAIMS:-}" == "Yes" ]]; then
      jit_lines+=$'\nauth-saml-sp-attribute-groups=http://schemas.microsoft.com/ws/2008/06/identity/claims/groups'
    fi
  fi

  cat <<EOF
# Append SAML settings to rserver.conf
cat >> /etc/rstudio/rserver.conf <<'RSERVER'

# --- Entra ID SAML ---
auth-saml=1
auth-saml-metadata-url=$SAML_METADATA_URL
auth-saml-sp-name-id-format=emailaddress
auth-saml-sp-attribute-username=NameID${jit_lines}
RSERVER

# Restart Workbench
sudo rstudio-server restart
EOF
}
```

Key details from kapa research:
- `auth-saml=1` enables SAML
- `auth-saml-metadata-url` points to Entra federation metadata
- `auth-saml-sp-name-id-format=emailaddress` — username will be email
- `auth-saml-sp-attribute-username=NameID` — use the NameID from assertion
- JIT settings go in same file
- Group attribute for SAML: `http://schemas.microsoft.com/ws/2008/06/identity/claims/groups` (the azure SAML claim URI)
- No client secret file needed

## Output Dispatch Changes

Current:
```bash
case "$PRODUCT" in
  workbench)      emit_workbench_commands ;;
  connect)        emit_connect_commands ;;
  packagemanager) emit_packagemanager_commands ;;
esac
```

New:
```bash
case "$PRODUCT" in
  workbench)
    if [[ "$AUTH_PROTOCOL" == "saml" ]]; then
      emit_workbench_saml_commands
    else
      emit_workbench_commands
    fi
    ;;
  connect)
    if [[ "$AUTH_PROTOCOL" == "saml" ]]; then
      emit_connect_saml_commands
    else
      emit_connect_commands
    fi
    ;;
  packagemanager) emit_packagemanager_commands ;;
esac
```

## Summary Banner Changes

For SAML, the summary banner differs slightly — no client secret or redirect URI:
```
=== Entra ID SAML registration complete for $PRODUCT_LABEL ===

Tenant ID:             $TENANT_ID
Client/App ID:         $CLIENT_ID
Entity ID:             $SAML_ENTITY_ID
ACS URL:               $SAML_ACS_URL
Metadata URL:          $SAML_METADATA_URL
Enterprise App SP ID:  $SP_OBJECT_ID

Enterprise App:        https://portal.azure.com/...
```

Need to split the summary section into OIDC vs SAML branches.
