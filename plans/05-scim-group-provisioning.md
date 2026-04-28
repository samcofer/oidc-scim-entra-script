# Step 5: SCIM Group Provisioning

## What Changes
When SCIM provisioning is configured for Workbench, add a prompt to enable group provisioning. This enables the "Provision Azure Active Directory Groups" mapping in the SCIM sync job schema.

## Current SCIM Flow
1. Instantiate template → get SP
2. Create sync job (templateId: "scim")
3. Save credentials (BaseAddress + SecretToken)
4. Optionally start job

Currently only user provisioning is configured. Group provisioning requires enabling the group mapping in the sync job schema.

## New Env Var
- `ENABLE_SCIM_GROUPS` — accepts `Yes`/`No`. Default: not set (interactive prompt).

## Prompt Location
After the existing SCIM prompts (SCIM_URL, SCIM_TOKEN, START_SCIM), before Azure API calls:
```
Enable SCIM group provisioning? [Yes/No, default Yes]:
```

Default is Yes because group provisioning is a common requirement alongside user provisioning.

## Graph API for Enabling Group Provisioning

After the sync job is created, we need to update its schema to enable group provisioning. The sync job schema has object mappings for both users and groups, but groups may be disabled by default.

### Approach: Update sync job schema
```
GET /v1.0/servicePrincipals/{sp-id}/synchronization/jobs/{job-id}/schema
```

This returns the schema with `synchronizationRules[].objectMappings[]`. Each mapping has a `name` and `enabled` flag. We need to find the group mapping and set `enabled: true`.

Then:
```
PUT /v1.0/servicePrincipals/{sp-id}/synchronization/jobs/{job-id}/schema
Body: <full schema with group mapping enabled>
```

### Implementation Detail
The schema is large and complex. Rather than downloading, modifying, and re-uploading the entire schema, we can use a more targeted approach:

Actually, for non-gallery SCIM apps, group provisioning may need to be configured differently. The default SCIM template should already support groups if the SCIM endpoint supports them.

**Alternative approach**: Entra ID's SCIM provisioning automatically discovers supported resources from the SCIM endpoint's `/Schemas` and `/ResourceTypes` endpoints. If Workbench's SCIM endpoint advertises group support (which it does), Entra may already provision groups.

However, in the Azure portal, group provisioning is a separate toggle in the "Mappings" blade. Via Graph API, this corresponds to enabling the group object mapping in the sync job schema.

### Simplified Approach
After creating the sync job, if `ENABLE_SCIM_GROUPS=Yes`:

1. GET the schema
2. Find the objectMapping where `sourceObjectName` = `Group` (or `name` contains "Group")
3. Set `enabled: true`
4. PUT the modified schema back

```bash
if [[ "$ENABLE_SCIM_GROUPS" == "Yes" ]]; then
  echo "Enabling SCIM group provisioning..."
  SCHEMA_JSON="$(az rest --method GET \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SCIM_SP_ID/synchronization/jobs/$SCIM_JOB_ID/schema" \
    -o json)"

  UPDATED_SCHEMA="$(echo "$SCHEMA_JSON" | jq '
    .synchronizationRules[].objectMappings |= map(
      if .sourceObjectName == "Group" then .enabled = true else . end
    )')"

  az rest --method PUT \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SCIM_SP_ID/synchronization/jobs/$SCIM_JOB_ID/schema" \
    --headers "Content-Type=application/json" \
    --body "$UPDATED_SCHEMA" >/dev/null
fi
```

**Note**: The schema PUT payload is large. In bash we can pass it inline since jq handles it. In PowerShell, we must write to a temp file (consistent with existing pattern).

## Config Output Impact

When SCIM groups are enabled, add to the Workbench rserver.conf output:
```
group-provisioning-start-gid=1000
```

This is only needed if `user-provisioning-enabled=1` is also set (which it is when SCIM is configured). If JIT is already adding `user-provisioning-enabled=1`, no duplication needed — just add the gid line.

Actually, `user-provisioning-enabled=1` is the prerequisite for SCIM to work at all. It should already be in the output when SCIM is configured, even without JIT. Let me check the current output...

Current `emit_workbench_commands` does NOT include `user-provisioning-enabled=1`. That's because the current scripts assume the user has already enabled user provisioning on the Workbench server (it's a prerequisite for SCIM). 

**Decision**: Add `user-provisioning-enabled=1` to the Workbench output when SCIM is configured, since we're already doing the Entra side setup. Also add `group-provisioning-start-gid=1000` when SCIM groups are enabled.

## Updated Workbench Output (SCIM section)

Add a new section to the Workbench output after the auth config:
```bash
emit_workbench_scim_config() {
  local lines="user-provisioning-enabled=1"
  if [[ "${ENABLE_SCIM_GROUPS:-}" == "Yes" ]]; then
    lines+=$'\ngroup-provisioning-start-gid=1000'
  fi
  cat <<EOF

# Enable user provisioning for SCIM
cat >> /etc/rstudio/rserver.conf <<'RSERVER'

$lines
RSERVER
EOF
}
```

Actually, this should be merged into the main auth emit function to avoid multiple appends to the same file. Let me reconsider — a single `cat >>` with all settings is cleaner.
