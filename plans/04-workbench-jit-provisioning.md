# Step 4: Workbench JIT Provisioning

## What Changes
Add a prompt for JIT (Just-In-Time) provisioning when configuring Workbench with OIDC or SAML (not SCIM-only mode). JIT provisions user accounts on first login, and dynamically adjusts group membership based on IdP claims.

## When JIT Applies
- **Workbench only** — Connect and PPM don't have JIT provisioning
- **OIDC mode** (mode 2: OIDC-only) or **SAML mode** (mode 2: SAML-only)
- **OIDC+SCIM / SAML+SCIM mode** (mode 1) — JIT can complement SCIM, but typically you use one or the other. We'll still offer the prompt.
- **NOT** SCIM-only mode (mode 3) — no auth means no login-time provisioning

## New Env Var
- `ENABLE_JIT` — accepts `Yes`/`No`. Default: not set (interactive prompt).

## Prompt Location
After the auth app creation and SCIM prompts (if any), before output. Actually, better: collect it with the other prompts, before any Azure API calls.

For the prompt flow:
1. Product selection
2. Auth protocol selection
3. Workbench mode selection (if workbench)
4. Auth app prompts (APP_NAME, BASE_URL, etc.)
5. **NEW: JIT prompt** (if workbench and not SCIM-only)
6. SCIM prompts (if applicable)
7. Azure API calls
8. Output

## Prompt
```
Enable JIT (Just-In-Time) user provisioning? [Yes/No, default No]:
```

When JIT is enabled, also ask about group provisioning via JIT:
- Actually, JIT group provisioning is automatic when groups claim is configured. If INCLUDE_GROUP_CLAIMS=Yes and JIT is enabled, groups are provisioned on login.
- So no separate prompt needed for JIT groups — it's driven by the existing INCLUDE_GROUP_CLAIMS setting.

## Config Output Impact

### OIDC + JIT (rserver.conf)
```
auth-openid=1
auth-openid-issuer=<issuer>
auth-openid-username-claim=preferred_username
auth-openid-groups-claim=groups
user-provisioning-enabled=1
user-provisioning-register-on-first-login=1
```

Note: `auth-openid-groups-claim=groups` is the OIDC claim name. It's `groups` by default when using Entra ID with groupMembershipClaims set.

### SAML + JIT (rserver.conf)
```
auth-saml=1
auth-saml-metadata-url=<metadata-url>
auth-saml-sp-name-id-format=emailaddress
auth-saml-sp-attribute-username=NameID
auth-saml-sp-attribute-groups=http://schemas.microsoft.com/ws/2008/06/identity/claims/groups
user-provisioning-enabled=1
user-provisioning-register-on-first-login=1
```

Note: For SAML, the groups attribute is the full SAML claim URI, not just "groups".

### OIDC+SCIM+JIT or SAML+SCIM+JIT
Both JIT and SCIM lines appear. This is valid — JIT handles login-time provisioning, SCIM handles background sync. They complement each other.

## Implementation in emit_workbench_commands (OIDC)

Add JIT lines to the existing function:
```bash
emit_workbench_commands() {
  local jit_lines=""
  if [[ "${ENABLE_JIT:-}" == "Yes" ]]; then
    jit_lines=$'\nuser-provisioning-enabled=1\nuser-provisioning-register-on-first-login=1'
    if [[ "${INCLUDE_GROUP_CLAIMS:-}" == "Yes" ]]; then
      jit_lines+=$'\nauth-openid-groups-claim=groups'
    fi
  fi

  cat <<EOF
# Append OIDC settings to rserver.conf
cat >> /etc/rstudio/rserver.conf <<'RSERVER'

# --- Entra ID OpenID Connect ---
auth-openid=1
auth-openid-issuer=$ISSUER
auth-openid-username-claim=preferred_username${jit_lines}
RSERVER
...
EOF
}
```

## SCIM interaction
When both JIT and SCIM are enabled, the SCIM output section also appears (provisioning job, etc.). The rserver.conf gets `user-provisioning-enabled=1` from JIT, which is also required for SCIM. No conflict.
