#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null || { echo "Missing required command: $1"; exit 1; }; }
need az
need jq

normalize_yesno() {
  case "${1,,}" in
    y|yes) echo "Yes" ;;
    n|no)  echo "No" ;;
    *)     return 1 ;;
  esac
}

validate_https_url() {
  local url="$1" suffix="${2:-}"
  if [[ ! "$url" =~ ^https:// ]]; then
    echo "URL must start with https://"
    return 1
  fi
  if [[ -n "$suffix" && "$url" != *"$suffix" ]]; then
    echo "URL must end with $suffix"
    return 1
  fi
  return 0
}

prompt() {
  local var="$1" label="$2" default="${3:-}" secret="${4:-false}"
  [[ -n "${!var:-}" ]] && return 0

  local value
  while true; do
    if [[ "$secret" == "true" ]]; then
      read -rsp "$label${default:+ [$default]}: " value </dev/tty
    else
      read -rp "$label${default:+ [$default]}: " value </dev/tty
    fi
    echo
    value="${value:-$default}"
    if [[ -n "$value" ]]; then break; fi
    echo "A value is required."
  done

  export "$var=$value"
}

prompt_url() {
  local var="$1" label="$2" default="${3:-}" suffix="${4:-}"

  if [[ -n "${!var:-}" ]]; then
    validate_https_url "${!var}" "$suffix" || exit 1
    return 0
  fi

  while true; do
    read -rp "$label${default:+ [$default]}: " value </dev/tty
    echo
    value="${value:-$default}"
    if [[ -z "$value" ]]; then
      echo "A value is required."
      continue
    fi
    if validate_https_url "$value" "$suffix"; then break; fi
  done

  export "$var=$value"
}

yesno() {
  local var="$1" label="$2" default="${3:-No}" value normalized

  if [[ -n "${!var:-}" ]]; then
    normalized="$(normalize_yesno "${!var}")" || {
      echo "Invalid value for $var: ${!var}. Use Yes or No."
      exit 1
    }
    export "$var=$normalized"
    return 0
  fi

  while true; do
    read -rp "$label [Yes/No, default $default]: " value </dev/tty
    echo
    value="${value:-$default}"

    normalized="$(normalize_yesno "$value")" && break
    echo "Please enter Yes or No."
  done

  export "$var=$normalized"
}

POSIT_LOGO_PNG_B64="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"

set_app_logo() {
  local app_object_id="$1"
  echo "Setting application logo..."
  local logo_file
  logo_file="$(mktemp)"
  echo -n "$POSIT_LOGO_PNG_B64" | base64 -d > "$logo_file"
  local token
  token="$(az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv)"
  if curl -sf -X PUT \
    "https://graph.microsoft.com/v1.0/applications/$app_object_id/logo" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: image/png" \
    --data-binary "@$logo_file" >/dev/null 2>&1; then
    echo "Application logo set."
  else
    echo "WARNING: Failed to set application logo (non-fatal)."
  fi
  rm -f "$logo_file"
}

truncate_name() {
  local base="$1" suffix="$2" max="${3:-120}"
  local allowed=$((max - ${#suffix}))

  if (( allowed < 1 )); then
    printf "%s" "${suffix:0:$max}"
  else
    printf "%s%s" "${base:0:$allowed}" "$suffix"
  fi
}

select_product() {
  if [[ -n "${PRODUCT:-}" ]]; then
    case "${PRODUCT,,}" in
      workbench|1) PRODUCT="workbench" ;;
      connect|2)   PRODUCT="connect" ;;
      packagemanager|ppm|3) PRODUCT="packagemanager" ;;
      *) echo "Invalid PRODUCT value: $PRODUCT"; exit 1 ;;
    esac
    return 0
  fi

  echo ""
  echo "Select Posit product to configure:"
  echo "  1) Posit Workbench"
  echo "  2) Posit Connect"
  echo "  3) Posit Package Manager"
  echo ""

  local choice
  while true; do
    read -rp "Product [1/2/3]: " choice </dev/tty
    echo
    case "$choice" in
      1|workbench)      PRODUCT="workbench"; break ;;
      2|connect)        PRODUCT="connect"; break ;;
      3|packagemanager|ppm) PRODUCT="packagemanager"; break ;;
      *) echo "Please enter 1, 2, or 3." ;;
    esac
  done

  export PRODUCT
}

print_collected_info() {
  cat <<EOF

Collected information so far
============================

Product:                ${PRODUCT:-}
Tenant ID:              ${TENANT_ID:-}
Skip OIDC:              ${SKIP_OIDC:-}

OIDC:
  App name:             ${APP_NAME:-}
  Base URL:             ${BASE_URL:-}
  Redirect URI:         ${REDIRECT_URI:-}
  Client secret name:   ${CLIENT_SECRET_NAME:-}
  Sign-in audience:     ${SIGNIN_AUDIENCE:-}
  Include groups:       ${INCLUDE_GROUP_CLAIMS:-}
  Group claim mode:     ${GROUP_CLAIMS:-}
  Client ID:            ${CLIENT_ID:-}
  App object ID:        ${APP_OBJECT_ID:-}
  Enterprise SP ID:     ${SP_OBJECT_ID:-}

SCIM:
  Create SCIM:          ${CREATE_SCIM:-}
  App name:             ${SCIM_APP_NAME:-}
  SCIM URL:             ${SCIM_URL:-}
  SCIM app/client ID:   ${SCIM_APP_ID:-}
  SCIM SP ID:           ${SCIM_SP_ID:-}
  SCIM job ID:          ${SCIM_JOB_ID:-}
  Start SCIM:           ${START_SCIM:-}

Secrets:
  OIDC client secret:   ${CLIENT_SECRET:-}
  SCIM token:           ${SCIM_TOKEN:+<collected but hidden>}
EOF
}

on_error() {
  local exit_code=$?
  echo
  echo "Script failed with exit code $exit_code."
  print_collected_info
  exit "$exit_code"
}

trap on_error ERR

echo "Checking Azure login..."
ACCOUNT_JSON="$(az account show -o json)"

TENANT_ID="$(jq -r '.tenantId' <<<"$ACCOUNT_JSON")"
SIGNED_IN_USER="$(az ad signed-in-user show --query id -o tsv)"
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"
GRAPH_SP_ID="$(az ad sp show --id "$GRAPH_APP_ID" --query id -o tsv)"
SCIM_TEMPLATE_ID="8adf8e6e-67b2-4cf2-a259-e3dc5476c621"

select_product

case "$PRODUCT" in
  workbench)
    DEFAULT_APP_NAME="posit-workbench-oidc"
    PRODUCT_LABEL="Posit Workbench"
    URL_EXAMPLE="https://workbench.example.com"
    ;;
  connect)
    DEFAULT_APP_NAME="posit-connect-oidc"
    PRODUCT_LABEL="Posit Connect"
    URL_EXAMPLE="https://connect.example.com"
    ;;
  packagemanager)
    DEFAULT_APP_NAME="posit-package-manager-oidc"
    PRODUCT_LABEL="Posit Package Manager"
    URL_EXAMPLE="https://packagemanager.example.com"
    ;;
esac

echo ""
echo "Configuring Entra ID for $PRODUCT_LABEL"
echo "========================================"

if [[ "$PRODUCT" == "workbench" ]]; then
  if [[ -n "${WB_MODE:-}" ]]; then
    case "${WB_MODE,,}" in
      1|oidc-scim|oidc+scim) SKIP_OIDC="No";  CREATE_SCIM="Yes" ;;
      2|oidc)                SKIP_OIDC="No";  CREATE_SCIM="No" ;;
      3|scim)                SKIP_OIDC="Yes"; CREATE_SCIM="Yes" ;;
      *) echo "Invalid WB_MODE value: $WB_MODE. Use oidc+scim, oidc, or scim."; exit 1 ;;
    esac
  else
    echo ""
    echo "Select Workbench configuration mode:"
    echo "  1) OIDC + SCIM provisioning"
    echo "  2) OIDC only"
    echo "  3) SCIM provisioning only"
    echo ""
    while true; do
      read -rp "Mode [1/2/3]: " wb_choice </dev/tty
      echo
      case "$wb_choice" in
        1) SKIP_OIDC="No";  CREATE_SCIM="Yes"; break ;;
        2) SKIP_OIDC="No";  CREATE_SCIM="No";  break ;;
        3) SKIP_OIDC="Yes"; CREATE_SCIM="Yes"; break ;;
        *) echo "Please enter 1, 2, or 3." ;;
      esac
    done
  fi
else
  SKIP_OIDC="No"
  CREATE_SCIM="No"
fi

if [[ "$SKIP_OIDC" != "Yes" ]]; then
  prompt APP_NAME "App registration name" "$DEFAULT_APP_NAME"
  prompt_url BASE_URL "$PRODUCT_LABEL base URL" "$URL_EXAMPLE"

  case "$PRODUCT" in
    workbench)
      DEFAULT_REDIRECT="${BASE_URL%/}/openid/callback"
      REDIRECT_SUFFIX="/openid/callback"
      ;;
    connect|packagemanager)
      DEFAULT_REDIRECT="${BASE_URL%/}/__login__/callback"
      REDIRECT_SUFFIX="/__login__/callback"
      ;;
  esac

  prompt_url REDIRECT_URI "OIDC redirect URI" "$DEFAULT_REDIRECT" "$REDIRECT_SUFFIX"
  prompt CLIENT_SECRET_NAME "Client secret display name" "${APP_NAME}-secret"
  prompt SIGNIN_AUDIENCE "Sign-in audience: AzureADMyOrg, AzureADMultipleOrgs" "AzureADMyOrg"
  yesno INCLUDE_GROUP_CLAIMS "Include group claims in ID/access tokens?" "Yes"
  prompt GROUP_CLAIMS "Group claim mode: SecurityGroup, All, DirectoryRole, ApplicationGroup, None" "SecurityGroup"

  if [[ "$INCLUDE_GROUP_CLAIMS" == "Yes" ]]; then
    GROUP_MEMBERSHIP_CLAIMS="$GROUP_CLAIMS"
  else
    GROUP_MEMBERSHIP_CLAIMS="None"
  fi

  # --- Collect SCIM prompts early for unified mode ---
  if [[ "$CREATE_SCIM" == "Yes" ]]; then
    DEFAULT_SCIM_URL="${BASE_URL%/}/scim/v2"
    prompt_url SCIM_URL "Workbench SCIM base URL" "$DEFAULT_SCIM_URL" "/scim/v2"

    echo "Testing SCIM endpoint reachability..."
    if curl -sk --connect-timeout 10 -o /dev/null -w '' "$SCIM_URL" 2>/dev/null; then
      echo "SCIM endpoint is reachable."
    else
      echo "WARNING: SCIM endpoint at $SCIM_URL is not reachable from this environment."
      yesno SCIM_CONNECTIVITY_CONFIRMED "Do you have connectivity between Azure and your Workbench instance handled via another avenue (e.g., VPN, private endpoint)?" "No"
      if [[ "$SCIM_CONNECTIVITY_CONFIRMED" != "Yes" ]]; then
        echo "Skipping SCIM provisioning. SCIM requires network connectivity from Azure to your Workbench instance."
        CREATE_SCIM="No"
      fi
    fi

    if [[ "$CREATE_SCIM" == "Yes" ]]; then
      prompt SCIM_TOKEN "Workbench SCIM bearer token" "" true
      yesno START_SCIM "Start SCIM provisioning job now?" "No"
    fi
  fi

  # --- Create app registration ---
  if [[ "$CREATE_SCIM" == "Yes" ]]; then
    echo "Creating unified OIDC+SCIM app from Microsoft template..."
    TEMPLATE_JSON="$(az rest --method POST \
      --url "https://graph.microsoft.com/v1.0/applicationTemplates/$SCIM_TEMPLATE_ID/instantiate" \
      --headers "Content-Type=application/json" \
      --body "$(jq -n --arg name "$APP_NAME" '{displayName: $name}')" \
      -o json)"

    SP_OBJECT_ID="$(jq -r '.servicePrincipal.id // empty' <<<"$TEMPLATE_JSON")"
    CLIENT_ID="$(jq -r '.application.appId // empty' <<<"$TEMPLATE_JSON")"

    if [[ -z "$SP_OBJECT_ID" ]]; then
      echo "Template instantiation did not return a service principal ID."
      echo "$TEMPLATE_JSON"
      exit 1
    fi

    echo "Waiting for service principal to become available..."
    for i in $(seq 1 12); do
      if az ad sp show --id "$SP_OBJECT_ID" -o none 2>/dev/null; then break; fi
      if (( i == 12 )); then
        echo "Timed out waiting for service principal $SP_OBJECT_ID to become available." >&2
        exit 1
      fi
      sleep 5
    done

    APP_OBJECT_ID="$(az ad app show --id "$CLIENT_ID" --query id -o tsv)"

    echo "Configuring app registration with OIDC settings..."
    az rest --method PATCH \
      --url "https://graph.microsoft.com/v1.0/applications/$APP_OBJECT_ID" \
      --headers "Content-Type=application/json" \
      --body "$(jq -n \
        --arg audience "$SIGNIN_AUDIENCE" \
        --arg uri "$REDIRECT_URI" \
        --arg groups "$GROUP_MEMBERSHIP_CLAIMS" \
        '{
          signInAudience: $audience,
          groupMembershipClaims: $groups,
          web: {
            redirectUris: [$uri],
            implicitGrantSettings: {
              enableIdTokenIssuance: true,
              enableAccessTokenIssuance: false
            }
          },
          optionalClaims: {
            idToken: [
              {name: "email", essential: false},
              {name: "preferred_username", essential: false}
            ]
          }
        }')" \
      >/dev/null
  else
    echo "Creating OIDC app registration..."
    APP_JSON="$(az rest --method POST \
      --url "https://graph.microsoft.com/v1.0/applications" \
      --headers "Content-Type=application/json" \
      --body "$(jq -n \
        --arg name "$APP_NAME" \
        --arg audience "$SIGNIN_AUDIENCE" \
        --arg uri "$REDIRECT_URI" \
        --arg groups "$GROUP_MEMBERSHIP_CLAIMS" \
        '{
          displayName: $name,
          signInAudience: $audience,
          groupMembershipClaims: $groups,
          web: {
            redirectUris: [$uri],
            implicitGrantSettings: {
              enableIdTokenIssuance: true,
              enableAccessTokenIssuance: false
            }
          },
          optionalClaims: {
            idToken: [
              {name: "email", essential: false},
              {name: "preferred_username", essential: false}
            ]
          }
        }')" \
      -o json)"

    APP_OBJECT_ID="$(jq -r '.id' <<<"$APP_JSON")"
    CLIENT_ID="$(jq -r '.appId' <<<"$APP_JSON")"
  fi

  set_app_logo "$APP_OBJECT_ID"

  echo "Adding OpenID delegated permissions..."
  if ! perm_output="$(az ad app permission add --id "$CLIENT_ID" --api "$GRAPH_APP_ID" --api-permissions \
    "37f7f235-527c-4136-accd-4a02d197296e=Scope" \
    "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0=Scope" \
    "14dad69e-099b-42c9-810b-d002981feec1=Scope" \
    "7427e0e9-2fba-42fe-b0c0-848c9e6a818b=Scope" \
    "e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope" 2>&1)"; then
    if [[ "$perm_output" != *"already exist"* ]]; then
      echo "Failed to add permissions: $perm_output" >&2
      exit 1
    fi
  fi

  echo "Creating client secret..."
  SECRET_JSON="$(az rest --method POST \
    --url "https://graph.microsoft.com/v1.0/applications/$APP_OBJECT_ID/addPassword" \
    --headers "Content-Type=application/json" \
    --body "$(jq -n --arg name "$CLIENT_SECRET_NAME" \
      '{passwordCredential: {displayName: $name}}')" \
    -o json 2>/dev/null)"

  CLIENT_SECRET="$(jq -r '.secretText' <<<"$SECRET_JSON")"

  echo "Adding signed-in user as app owner..."
  az rest --method POST \
    --url "https://graph.microsoft.com/v1.0/applications/$APP_OBJECT_ID/owners/\$ref" \
    --headers "Content-Type=application/json" \
    --body "$(jq -n --arg id "https://graph.microsoft.com/v1.0/directoryObjects/$SIGNED_IN_USER" \
      '{"@odata.id": $id}')" >/dev/null 2>&1 || true

  if [[ -z "${SP_OBJECT_ID:-}" ]]; then
    echo "Creating/ensuring enterprise service principal..."
    az ad sp create --id "$CLIENT_ID" >/dev/null 2>&1 || true
    for i in $(seq 1 6); do
      SP_OBJECT_ID="$(az ad sp show --id "$CLIENT_ID" --query id -o tsv 2>/dev/null)" && [[ -n "$SP_OBJECT_ID" ]] && break
      if (( i == 6 )); then
        echo "Timed out waiting for service principal for $CLIENT_ID to become available." >&2
        exit 1
      fi
      sleep 5
    done
  fi

  az rest --method POST \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJECT_ID/owners/\$ref" \
    --headers "Content-Type=application/json" \
    --body "$(jq -n --arg id "https://graph.microsoft.com/v1.0/directoryObjects/$SIGNED_IN_USER" \
      '{"@odata.id": $id}')" >/dev/null 2>&1 || true

  echo "Granting admin consent for delegated permissions..."
  az rest --method POST \
    --url "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" \
    --headers "Content-Type=application/json" \
    --body "$(jq -n \
      --arg clientId "$SP_OBJECT_ID" \
      --arg resourceId "$GRAPH_SP_ID" \
      '{
        clientId: $clientId,
        consentType: "AllPrincipals",
        resourceId: $resourceId,
        scope: "email offline_access openid profile User.Read"
      }')" \
    -o json >/dev/null

  echo "Requiring user assignment on enterprise app..."
  az rest --method PATCH \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJECT_ID" \
    --headers "Content-Type=application/json" \
    --body "$(jq -n '{appRoleAssignmentRequired: true}')" \
    >/dev/null

  echo "Assigning signed-in user to enterprise app..."
  APP_ROLE_ID="$(az rest --method GET \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJECT_ID" \
    -o json | jq -r '[.appRoles[] | select(.isEnabled == true)] | if length > 0 then .[0].id else "00000000-0000-0000-0000-000000000000" end')"
  az rest --method POST \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJECT_ID/appRoleAssignedTo" \
    --headers "Content-Type=application/json" \
    --body "$(jq -n \
      --arg principalId "$SIGNED_IN_USER" \
      --arg resourceId "$SP_OBJECT_ID" \
      --arg appRoleId "$APP_ROLE_ID" \
      '{
        principalId: $principalId,
        resourceId: $resourceId,
        appRoleId: $appRoleId
      }')" \
    >/dev/null

else
  prompt_url BASE_URL "$PRODUCT_LABEL base URL" "$URL_EXAMPLE"
  APP_NAME="${APP_NAME:-$DEFAULT_APP_NAME}"
fi

# --- SCIM provisioning (Workbench only) ---

SCIM_OUTPUT=""
if [[ "$CREATE_SCIM" == "Yes" ]]; then
  if [[ "$SKIP_OIDC" == "Yes" ]]; then
    # Mode 3 (SCIM only): standalone SCIM app
    DEFAULT_SCIM_APP_NAME="$(truncate_name "$APP_NAME" "-scim-provisioning" 120)"
    DEFAULT_SCIM_URL="${BASE_URL%/}/scim/v2"

    prompt SCIM_APP_NAME "SCIM enterprise app name" "$DEFAULT_SCIM_APP_NAME"
    prompt_url SCIM_URL "Workbench SCIM base URL" "$DEFAULT_SCIM_URL" "/scim/v2"

    echo "Testing SCIM endpoint reachability..."
    if curl -sk --connect-timeout 10 -o /dev/null -w '' "$SCIM_URL" 2>/dev/null; then
      echo "SCIM endpoint is reachable."
    else
      echo "WARNING: SCIM endpoint at $SCIM_URL is not reachable from this environment."
      yesno SCIM_CONNECTIVITY_CONFIRMED "Do you have connectivity between Azure and your Workbench instance handled via another avenue (e.g., VPN, private endpoint)?" "No"
      if [[ "$SCIM_CONNECTIVITY_CONFIRMED" != "Yes" ]]; then
        echo "Skipping SCIM provisioning. SCIM requires network connectivity from Azure to your Workbench instance."
        CREATE_SCIM="No"
      fi
    fi
  fi
fi

if [[ "$CREATE_SCIM" == "Yes" ]]; then
  if [[ "$SKIP_OIDC" == "Yes" ]]; then
    # Mode 3: collect remaining prompts and create standalone SCIM app
    prompt SCIM_TOKEN "Workbench SCIM bearer token" "" true
    yesno START_SCIM "Start SCIM provisioning job now?" "No"

    echo "Creating SCIM enterprise application from Microsoft template..."
    SCIM_APP_JSON="$(az rest --method POST \
      --url "https://graph.microsoft.com/v1.0/applicationTemplates/$SCIM_TEMPLATE_ID/instantiate" \
      --headers "Content-Type=application/json" \
      --body "$(jq -n --arg name "$SCIM_APP_NAME" '{displayName: $name}')" \
      -o json)"

    SCIM_SP_ID="$(jq -r '.servicePrincipal.id // empty' <<<"$SCIM_APP_JSON")"
    SCIM_APP_ID="$(jq -r '.application.appId // empty' <<<"$SCIM_APP_JSON")"

    if [[ -z "$SCIM_SP_ID" ]]; then
      echo "SCIM application creation did not return a service principal ID."
      echo "$SCIM_APP_JSON"
      exit 1
    fi

    echo "Waiting for SCIM service principal to become available..."
    for i in $(seq 1 12); do
      if az ad sp show --id "$SCIM_SP_ID" -o none 2>/dev/null; then break; fi
      if (( i == 12 )); then
        echo "Timed out waiting for service principal $SCIM_SP_ID to become available." >&2
        exit 1
      fi
      sleep 5
    done

    echo "Adding signed-in user as SCIM app owner..."
    SCIM_APP_OBJECT_ID="$(az ad app show --id "$SCIM_APP_ID" --query id -o tsv)"
    set_app_logo "$SCIM_APP_OBJECT_ID"
    az rest --method POST \
      --url "https://graph.microsoft.com/v1.0/applications/$SCIM_APP_OBJECT_ID/owners/\$ref" \
      --headers "Content-Type=application/json" \
      --body "$(jq -n --arg id "https://graph.microsoft.com/v1.0/directoryObjects/$SIGNED_IN_USER" \
        '{"@odata.id": $id}')" >/dev/null 2>&1 || true
    az rest --method POST \
      --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SCIM_SP_ID/owners/\$ref" \
      --headers "Content-Type=application/json" \
      --body "$(jq -n --arg id "https://graph.microsoft.com/v1.0/directoryObjects/$SIGNED_IN_USER" \
        '{"@odata.id": $id}')" >/dev/null 2>&1 || true
  else
    # Mode 1 (OIDC+SCIM unified): reuse the already-created SP
    SCIM_SP_ID="$SP_OBJECT_ID"
  fi

  echo "Waiting for provisioning readiness..."
  sleep 10

  echo "Creating SCIM provisioning job..."
  JOB_JSON="$(az rest --method POST \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SCIM_SP_ID/synchronization/jobs" \
    --headers "Content-Type=application/json" \
    --body '{"templateId":"scim"}' \
    -o json)"

  SCIM_JOB_ID="$(jq -r '.id // empty' <<<"$JOB_JSON")"

  if [[ -z "$SCIM_JOB_ID" ]]; then
    echo "SCIM provisioning job creation did not return a job ID."
    echo "$JOB_JSON"
    exit 1
  fi

  echo "Saving SCIM endpoint and token..."
  az rest --method PUT \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SCIM_SP_ID/synchronization/secrets" \
    --headers "Content-Type=application/json" \
    --body "$(jq -n --arg url "$SCIM_URL" --arg token "$SCIM_TOKEN" '{
      value: [
        {key: "BaseAddress", value: $url},
        {key: "SecretToken", value: $token}
      ]
    }')" >/dev/null

  if [[ "$START_SCIM" == "Yes" ]]; then
    echo "Starting SCIM provisioning job..."
    az rest --method POST \
      --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SCIM_SP_ID/synchronization/jobs/$SCIM_JOB_ID/start" \
      >/dev/null
  fi

  if [[ "$SKIP_OIDC" != "Yes" ]]; then
    SCIM_OUTPUT="
# SCIM Provisioning (same app):
#   Provisioning job ID: $SCIM_JOB_ID
#   SCIM URL:            $SCIM_URL
"
  else
    SCIM_OUTPUT="
# SCIM Enterprise App:
#   Display name:        $SCIM_APP_NAME
#   App/client ID:       $SCIM_APP_ID
#   Service principal:   $SCIM_SP_ID
#   Provisioning job ID: $SCIM_JOB_ID
#   SCIM URL:            $SCIM_URL
#   Enterprise App:      https://portal.azure.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/$SCIM_SP_ID/appId/$SCIM_APP_ID
"
  fi
fi

# --- Output configuration commands ---

ISSUER="https://login.microsoftonline.com/$TENANT_ID/v2.0"

emit_workbench_commands() {
  cat <<EOF
# Append OIDC settings to rserver.conf
cat >> /etc/rstudio/rserver.conf <<'RSERVER'

# --- Entra ID OpenID Connect ---
auth-openid=1
auth-openid-issuer=$ISSUER
auth-openid-username-claim=preferred_username
RSERVER

# Create client credentials file
cat > /etc/rstudio/openid-client-secret <<'SECRET'
client-id=$CLIENT_ID
client-secret=$CLIENT_SECRET
SECRET
chmod 0600 /etc/rstudio/openid-client-secret

# Restart Workbench
sudo rstudio-server restart
EOF
}

emit_connect_commands() {
  local groups_lines=""
  if [[ "$INCLUDE_GROUP_CLAIMS" == "Yes" ]]; then
    groups_lines=$'\nGroupsAutoProvision = true\nGroupsClaim = "groups"'
  fi

  cat <<EOF
# Change auth provider from password to oauth2
sudo sed -i 's/^Provider = "password"/Provider = "oauth2"/' /etc/rstudio-connect/rstudio-connect.gcfg

# Append OAuth2 settings
cat >> /etc/rstudio-connect/rstudio-connect.gcfg <<'GCFG'

[OAuth2]
ClientId = "$CLIENT_ID"
ClientSecret = "$CLIENT_SECRET"
OpenIDConnectIssuer = "$ISSUER"
RequireUsernameClaim = true
UsernameClaim = "preferred_username"${groups_lines}
GCFG

# Restart Connect
sudo systemctl restart rstudio-connect
EOF
}

emit_packagemanager_commands() {
  cat <<EOF
# Set the server address for OIDC callback support
sudo sed -i 's|^; Address = "http://posit-connect.example.com"|Address = "$BASE_URL"|' /etc/rstudio-pm/rstudio-pm.gcfg

# Append OpenID Connect settings
cat >> /etc/rstudio-pm/rstudio-pm.gcfg <<'GCFG'

[OpenIDConnect]
Issuer = "$ISSUER"
ClientId = "$CLIENT_ID"
ClientSecret = "$CLIENT_SECRET"
GCFG

# Restart Package Manager
sudo systemctl restart rstudio-pm
EOF
}

if [[ "$SKIP_OIDC" != "Yes" ]]; then
  cat <<EOF

=== Entra ID registration complete for $PRODUCT_LABEL ===

Tenant ID:             $TENANT_ID
Client ID:             $CLIENT_ID
Client secret:         $CLIENT_SECRET
Redirect URI:          $REDIRECT_URI
Issuer:                $ISSUER
Enterprise App SP ID:  $SP_OBJECT_ID

App Registration:      https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$CLIENT_ID
Enterprise App:        https://portal.azure.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/$SP_OBJECT_ID/appId/$CLIENT_ID
$SCIM_OUTPUT
Run the following commands on your $PRODUCT_LABEL server to configure OIDC:
==========================================================================

EOF

  case "$PRODUCT" in
    workbench)      emit_workbench_commands ;;
    connect)        emit_connect_commands ;;
    packagemanager) emit_packagemanager_commands ;;
  esac
else
  cat <<EOF

=== SCIM-only configuration complete for $PRODUCT_LABEL ===

Tenant ID: $TENANT_ID
$SCIM_OUTPUT
EOF
fi
