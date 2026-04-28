# Implementation Plan Overview

## Goal
Add SAML authentication support for Connect and Workbench, and add group-based provisioning (SCIM groups + JIT) for Workbench. Both bash and PS1 scripts must stay structurally aligned.

## New Features

### 1. Auth Protocol Selection (Connect + Workbench)
Currently the scripts only create OIDC app registrations. Add a prompt to choose between OIDC and SAML. PPM stays OIDC-only (no SAML support in PPM).

### 2. SAML Enterprise App Creation
SAML apps in Entra ID are "Enterprise Applications" created via template instantiation (same template as SCIM: `8adf8e6e-67b2-4cf2-a259-e3dc5476c621`). After creation, configure `preferredSingleSignOnMode=saml` and set SAML SSO URLs on the service principal.

### 3. SAML Config Output
- **Connect**: Output `[SAML]` section in gcfg with `IdPMetaDataURL`, `IdPAttributeProfile=azure`, `IdPSingleSignOnPostBinding=true`, `GroupsAutoProvision`
- **Workbench**: Output `auth-saml=1` settings in rserver.conf with metadata URL, name-id-format, attribute mappings

### 4. Workbench JIT Provisioning
Add prompts for JIT provisioning (`user-provisioning-enabled=1`, `user-provisioning-register-on-first-login=1`). Works with both OIDC and SAML. When enabled, add appropriate group claim attributes to the output.

### 5. SCIM Group Provisioning
When SCIM is configured, add a prompt to enable group provisioning. This enables the "Provision Azure Active Directory Groups" mapping in the SCIM sync schema. Output additional `group-provisioning-start-gid` config.

## Step-by-Step Plan Files
- `01-auth-protocol-selection.md` — New AUTH_PROTOCOL prompt and flow branching
- `02-saml-enterprise-app.md` — Graph API calls to create and configure SAML enterprise app
- `03-saml-config-output.md` — emit_*_saml_commands functions for Connect and Workbench
- `04-workbench-jit-provisioning.md` — JIT provisioning prompts and config output
- `05-scim-group-provisioning.md` — SCIM group provisioning schema enablement
- `06-powershell-mirror.md` — PS1 changes mirroring all bash changes
- `07-testing-plan.md` — Test matrix and env var combinations

## Structural Principle
Every change to the bash script has a corresponding change in the PS1 script. Changes are made to bash first, tested, then mirrored to PS1 and tested.
