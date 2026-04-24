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
  prompt APP_NAME "OIDC app registration name" "$DEFAULT_APP_NAME"
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

  # Microsoft Graph delegated permission GUIDs:
  #   openid          = 37f7f235-527c-4136-accd-4a02d197296e
  #   email           = 64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0
  #   profile         = 14dad69e-099b-42c9-810b-d002981feec1
  #   offline_access  = 7427e0e9-2fba-42fe-b0c0-848c9e6a818b
  #   User.Read       = e1fe6dd8-ba31-4d61-89e7-88639da4683d
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
    -o json)"

  CLIENT_SECRET="$(jq -r '.secretText' <<<"$SECRET_JSON")"

  echo "Adding signed-in user as app owner..."
  az rest --method POST \
    --url "https://graph.microsoft.com/v1.0/applications/$APP_OBJECT_ID/owners/\$ref" \
    --headers "Content-Type=application/json" \
    --body "$(jq -n --arg id "https://graph.microsoft.com/v1.0/directoryObjects/$SIGNED_IN_USER" \
      '{"@odata.id": $id}')" >/dev/null 2>&1 || true

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

  az rest --method POST \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJECT_ID/owners/\$ref" \
    --headers "Content-Type=application/json" \
    --body "$(jq -n --arg id "https://graph.microsoft.com/v1.0/directoryObjects/$SIGNED_IN_USER" \
      '{"@odata.id": $id}')" >/dev/null 2>&1 || true

  echo "Requiring user assignment on enterprise app..."
  az rest --method PATCH \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJECT_ID" \
    --headers "Content-Type=application/json" \
    --body "$(jq -n '{appRoleAssignmentRequired: true}')" \
    >/dev/null

  echo "Assigning signed-in user to enterprise app..."
  az rest --method POST \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJECT_ID/appRoleAssignedTo" \
    --headers "Content-Type=application/json" \
    --body "$(jq -n \
      --arg principalId "$SIGNED_IN_USER" \
      --arg resourceId "$SP_OBJECT_ID" \
      '{
        principalId: $principalId,
        resourceId: $resourceId,
        appRoleId: "00000000-0000-0000-0000-000000000000"
      }')" \
    >/dev/null

else
  prompt_url BASE_URL "$PRODUCT_LABEL base URL" "$URL_EXAMPLE"
  APP_NAME="${APP_NAME:-$DEFAULT_APP_NAME}"
fi

# --- SCIM (Workbench only) ---

SCIM_OUTPUT=""
if [[ "$CREATE_SCIM" == "Yes" ]]; then
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
      echo "SCIM provisioning requires network connectivity from Azure to your Workbench instance. Exiting."
      exit 1
    fi
  fi

  prompt SCIM_TOKEN "Workbench SCIM bearer token" "" true
  yesno START_SCIM "Start SCIM provisioning job now?" "No"

  echo "Creating non-gallery SCIM enterprise application from Microsoft template..."
  SCIM_TEMPLATE_ID="8adf8e6e-67b2-4cf2-a259-e3dc5476c621"

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
    if az ad sp show --id "$SCIM_SP_ID" -o none 2>/dev/null; then
      break
    fi
    if (( i == 12 )); then
      echo "Timed out waiting for service principal $SCIM_SP_ID to become available." >&2
      exit 1
    fi
    sleep 5
  done

  echo "Adding signed-in user as SCIM app owner..."
  SCIM_APP_OBJECT_ID="$(az ad app show --id "$SCIM_APP_ID" --query id -o tsv)"
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

  echo "Waiting for ownership to propagate..."
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

  SCIM_OUTPUT="
# SCIM Enterprise App:
#   Display name:        $SCIM_APP_NAME
#   App/client ID:       $SCIM_APP_ID
#   Service principal:   $SCIM_SP_ID
#   Provisioning job ID: $SCIM_JOB_ID
#   SCIM URL:            $SCIM_URL
"
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
