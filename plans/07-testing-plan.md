# Step 7: Testing Plan

## Test Matrix

Each row is a test run. Both bash and PS1 must be tested for each scenario.

### Bash Tests (direct execution)

| # | Product   | Protocol | Mode       | JIT | SCIM Groups | Test Name Prefix     |
|---|-----------|----------|------------|-----|-------------|----------------------|
| 1 | Connect   | SAML     | n/a        | n/a | n/a         | bash-test-con-saml   |
| 2 | Connect   | OIDC     | n/a        | n/a | n/a         | bash-test-con-oidc   |
| 3 | Workbench | SAML     | saml+scim  | Yes | Yes         | bash-test-wb-saml-sc |
| 4 | Workbench | SAML     | saml-only  | Yes | n/a         | bash-test-wb-saml    |
| 5 | Workbench | OIDC     | oidc+scim  | Yes | Yes         | bash-test-wb-oidc-sc |
| 6 | Workbench | OIDC     | oidc-only  | No  | n/a         | bash-test-wb-oidc    |
| 7 | Workbench | n/a      | scim-only  | n/a | Yes         | bash-test-wb-scim    |
| 8 | PPM       | OIDC     | n/a        | n/a | n/a         | bash-test-ppm-oidc   |

### PS1 Tests (via WSL→pwsh)

Same matrix with `ps-test-` prefix instead of `bash-test-`.

## Env Var Templates for Each Test

### Test 1: Connect SAML (bash)
```bash
PRODUCT=connect \
AUTH_PROTOCOL=saml \
APP_NAME=bash-test-con-saml \
BASE_URL=https://connect.test.example.com \
SIGNIN_AUDIENCE=AzureADMyOrg \
INCLUDE_GROUP_CLAIMS=Yes \
GROUP_CLAIMS=SecurityGroup \
bash posit-oidc-scim-entra-configuration.sh
```

### Test 2: Connect OIDC (bash) — regression test
```bash
PRODUCT=connect \
AUTH_PROTOCOL=oidc \
APP_NAME=bash-test-con-oidc \
BASE_URL=https://connect.test.example.com \
REDIRECT_URI=https://connect.test.example.com/__login__/callback \
CLIENT_SECRET_NAME=bash-test-con-oidc-secret \
SIGNIN_AUDIENCE=AzureADMyOrg \
INCLUDE_GROUP_CLAIMS=Yes \
GROUP_CLAIMS=SecurityGroup \
bash posit-oidc-scim-entra-configuration.sh
```

### Test 3: Workbench SAML+SCIM+JIT+Groups (bash)
```bash
PRODUCT=workbench \
AUTH_PROTOCOL=saml \
WB_MODE=saml+scim \
APP_NAME=bash-test-wb-saml-sc \
BASE_URL=https://workbench.test.example.com \
SIGNIN_AUDIENCE=AzureADMyOrg \
INCLUDE_GROUP_CLAIMS=Yes \
GROUP_CLAIMS=SecurityGroup \
ENABLE_JIT=Yes \
SCIM_URL=https://workbench.test.example.com/scim/v2 \
SCIM_CONNECTIVITY_CONFIRMED=Yes \
SCIM_TOKEN=fake-token-for-testing \
START_SCIM=No \
ENABLE_SCIM_GROUPS=Yes \
bash posit-oidc-scim-entra-configuration.sh
```

### Test 4: Workbench SAML-only+JIT (bash)
```bash
PRODUCT=workbench \
AUTH_PROTOCOL=saml \
WB_MODE=saml \
APP_NAME=bash-test-wb-saml \
BASE_URL=https://workbench.test.example.com \
SIGNIN_AUDIENCE=AzureADMyOrg \
INCLUDE_GROUP_CLAIMS=Yes \
GROUP_CLAIMS=SecurityGroup \
ENABLE_JIT=Yes \
bash posit-oidc-scim-entra-configuration.sh
```

### Test 5: Workbench OIDC+SCIM+JIT+Groups (bash) — regression + new JIT/groups
```bash
PRODUCT=workbench \
AUTH_PROTOCOL=oidc \
WB_MODE=oidc+scim \
APP_NAME=bash-test-wb-oidc-sc \
BASE_URL=https://workbench.test.example.com \
REDIRECT_URI=https://workbench.test.example.com/openid/callback \
CLIENT_SECRET_NAME=bash-test-wb-oidc-sc-secret \
SIGNIN_AUDIENCE=AzureADMyOrg \
INCLUDE_GROUP_CLAIMS=Yes \
GROUP_CLAIMS=SecurityGroup \
ENABLE_JIT=Yes \
SCIM_URL=https://workbench.test.example.com/scim/v2 \
SCIM_CONNECTIVITY_CONFIRMED=Yes \
SCIM_TOKEN=fake-token-for-testing \
START_SCIM=No \
ENABLE_SCIM_GROUPS=Yes \
bash posit-oidc-scim-entra-configuration.sh
```

### Test 6: Workbench OIDC-only (bash) — regression
```bash
PRODUCT=workbench \
AUTH_PROTOCOL=oidc \
WB_MODE=oidc \
APP_NAME=bash-test-wb-oidc \
BASE_URL=https://workbench.test.example.com \
REDIRECT_URI=https://workbench.test.example.com/openid/callback \
CLIENT_SECRET_NAME=bash-test-wb-oidc-secret \
SIGNIN_AUDIENCE=AzureADMyOrg \
INCLUDE_GROUP_CLAIMS=No \
GROUP_CLAIMS=None \
ENABLE_JIT=No \
bash posit-oidc-scim-entra-configuration.sh
```

### Test 7: Workbench SCIM-only+Groups (bash) — regression + groups
```bash
PRODUCT=workbench \
WB_MODE=scim \
APP_NAME=bash-test-wb-scim \
BASE_URL=https://workbench.test.example.com \
SCIM_URL=https://workbench.test.example.com/scim/v2 \
SCIM_CONNECTIVITY_CONFIRMED=Yes \
SCIM_TOKEN=fake-token-for-testing \
START_SCIM=No \
ENABLE_SCIM_GROUPS=Yes \
bash posit-oidc-scim-entra-configuration.sh
```

### Test 8: PPM OIDC (bash) — regression
```bash
PRODUCT=packagemanager \
APP_NAME=bash-test-ppm-oidc \
BASE_URL=https://ppm.test.example.com \
REDIRECT_URI=https://ppm.test.example.com/__login__/callback \
CLIENT_SECRET_NAME=bash-test-ppm-oidc-secret \
SIGNIN_AUDIENCE=AzureADMyOrg \
INCLUDE_GROUP_CLAIMS=No \
GROUP_CLAIMS=None \
bash posit-oidc-scim-entra-configuration.sh
```

## Verification Checklist per Test

1. Script completes without error
2. Azure resources created (check via `az ad app list --filter "startswith(displayName, '<prefix>')"`)
3. Output config is syntactically correct for the target product
4. For SAML: Enterprise app has `preferredSingleSignOnMode=saml`
5. For SCIM: Sync job exists, credentials saved
6. For SCIM Groups: Group mapping enabled in sync job schema
7. For JIT: Output includes `user-provisioning-enabled=1` and `user-provisioning-register-on-first-login=1`
8. Portal links in output are valid

## Cleanup

After all tests:
```bash
# List all test apps
az ad app list --filter "startswith(displayName, 'bash-test-') or startswith(displayName, 'ps-test-')" --query "[].{name:displayName, appId:appId}" -o table

# Delete each
for appId in $(az ad app list --filter "startswith(displayName, 'bash-test-') or startswith(displayName, 'ps-test-')" --query "[].appId" -o tsv); do
  az ad app delete --id "$appId"
done
```
