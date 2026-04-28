# Step 2: SAML Enterprise App Creation via Graph API

## What Changes
When `AUTH_PROTOCOL=saml`, create a SAML enterprise application instead of an OIDC app registration. SAML apps are always created via template instantiation (same non-gallery template as SCIM).

## Key Difference from OIDC
- **OIDC**: `POST /v1.0/applications` creates app reg, then `az ad sp create` for SP
- **OIDC+SCIM**: `POST /v1.0/applicationTemplates/{id}/instantiate` creates both, then PATCH app reg with OIDC settings
- **SAML**: `POST /v1.0/applicationTemplates/{id}/instantiate` creates both, then configure SP for SAML SSO
- **SAML+SCIM**: Same as SAML, but also create SCIM sync job on the same SP

## SAML-Specific Graph API Calls

### 1. Instantiate from template (same as unified OIDC+SCIM)
```
POST /v1.0/applicationTemplates/8adf8e6e-67b2-4cf2-a259-e3dc5476c621/instantiate
Body: {"displayName": "<app-name>"}
```
Returns: `servicePrincipal.id`, `application.appId`

### 2. Set preferred SSO mode to SAML
```
PATCH /v1.0/servicePrincipals/{sp-id}
Body: {"preferredSingleSignOnMode": "saml"}
```

### 3. Configure SAML SSO URLs on the service principal
The SAML identifier (Entity ID) and reply URL (ACS) are set differently per product:

**Connect:**
- Identifier (Entity ID): `https://<base-url>/__login__/saml`
- Reply URL (ACS): `https://<base-url>/__login__/saml/acs`

**Workbench:**
- Identifier (Entity ID): `https://<base-url>/saml/metadata`
- Reply URL (ACS): `https://<base-url>/saml/acs`
- Sign-on URL: `https://<base-url>`

Set these via:
```
PATCH /v1.0/servicePrincipals/{sp-id}
Body: {
  "preferredSingleSignOnMode": "saml",
  "loginUrl": "<sign-on-url>",    // only for Workbench (SP-initiated)
  "replyUrls": ["<acs-url>"]
}
```

And also set the identifierUris on the APP REGISTRATION:
```
PATCH /v1.0/applications/{app-object-id}
Body: {
  "identifierUris": ["<entity-id>"],
  "groupMembershipClaims": "<group-claims>"
}
```

**WAIT** — Actually, `identifierUris` requires verified domains in single-tenant apps. For SAML, the entity ID goes into `servicePrincipalNames` on the SP, not `identifierUris` on the app. Let me reconsider.

### Corrected: SAML identifier via servicePrincipalNames
The entity ID for SAML is typically added to the service principal's `servicePrincipalNames` array. But `PATCH /servicePrincipals/{id}` doesn't allow modifying `servicePrincipalNames` directly — they're derived from `identifierUris` on the app.

**Alternative approach**: Use the `identifierUris` on the application BUT use an `api://` scheme to avoid domain verification:
- Actually no — the Posit products expect the entity ID to be an HTTPS URL.

**Correct approach for non-gallery apps**: The entity ID and ACS URL are configured as part of the SAML SSO configuration. For non-gallery (custom) enterprise apps, we configure them via:

1. First add the entity ID to the app's `identifierUris`:
```
PATCH /v1.0/applications/{app-object-id}
Body: {"identifierUris": ["https://<base-url>/__login__/saml"]}
```
This requires the domain to be verified in the tenant, OR we use the `api://` format.

**Simplest approach**: Since non-gallery apps created via template have flexible identifier requirements, and we're in the tenant admin context, we can:
1. Set `identifierUris` on the application to the SAML entity ID
2. If domain verification blocks this, fall back to `api://{appId}` and document that the entity ID in Entra will be `api://{appId}` rather than the product URL

Actually, looking at how the Azure portal does it: when you configure SAML SSO for a non-gallery app, it sets `identifierUris` on the app registration to the entity ID. This works for non-gallery apps even without domain verification because the template-created apps have special handling.

**Let me test this assumption during implementation and adjust.**

### 4. No client secret needed for SAML
SAML authentication doesn't use client secrets — it uses certificate-based signing. The IdP (Entra) signs the SAML assertion with its own certificate. The SP (Posit product) validates using the IdP's public cert from the federation metadata.

So for SAML: skip the `addPassword` step entirely.

### 5. No delegated permissions needed for SAML
SAML doesn't use Graph API delegated permissions (openid, email, profile, etc). Those are OAuth2/OIDC concepts. Skip the `az ad app permission add` and `POST /oauth2PermissionGrants` steps.

### 6. Group claims still apply
`groupMembershipClaims` on the application still controls whether group GUIDs appear in the SAML assertion. This works the same as OIDC.

```
PATCH /v1.0/applications/{app-object-id}
Body: {"groupMembershipClaims": "SecurityGroup"}
```

## Prompts for SAML Path

When `AUTH_PROTOCOL=saml`, the prompts change:
- `APP_NAME` — still needed (default changes to `posit-<product>-saml`)
- `BASE_URL` — still needed
- **NO** `REDIRECT_URI` — SAML doesn't use redirect URIs; it uses ACS URLs computed from BASE_URL
- **NO** `CLIENT_SECRET_NAME` — no client secret for SAML
- `SIGNIN_AUDIENCE` — still needed (signInAudience on the app)
- `INCLUDE_GROUP_CLAIMS` + `GROUP_CLAIMS` — still needed (groupMembershipClaims)

## New Variables for SAML
- `SAML_ENTITY_ID` — computed from BASE_URL + product suffix, not prompted
- `SAML_ACS_URL` — computed from BASE_URL + product suffix, not prompted
- `SAML_METADATA_URL` — computed from tenant ID + app ID after creation

## Flow Summary (SAML path, no SCIM)

1. Prompt: APP_NAME, BASE_URL, SIGNIN_AUDIENCE, INCLUDE_GROUP_CLAIMS, GROUP_CLAIMS
2. Compute SAML_ENTITY_ID, SAML_ACS_URL from BASE_URL
3. Instantiate from template → get SP_OBJECT_ID, CLIENT_ID
4. Wait for SP availability
5. Get APP_OBJECT_ID from CLIENT_ID
6. PATCH application: identifierUris, groupMembershipClaims
7. PATCH service principal: preferredSingleSignOnMode=saml, loginUrl, replyUrls
8. Set logo
9. Add owner to app + SP
10. Require user assignment, assign signed-in user
11. Compute SAML_METADATA_URL
12. Output SAML config commands

## Flow Summary (SAML + SCIM, Workbench only)

Same as above but also:
- Collect SCIM prompts (SCIM_URL, SCIM_TOKEN, START_SCIM)
- Create SCIM sync job on the same SP
- Save SCIM credentials
- Optionally start SCIM job
