#Requires -Version 7.0
$ErrorActionPreference = 'Stop'

# --- Helper functions ---

function Prompt-Value {
    param(
        [string]$Name,
        [string]$Label,
        [string]$Default = '',
        [switch]$Secret
    )
    $envVal = [Environment]::GetEnvironmentVariable($Name)
    if ($envVal) { return $envVal }

    $prompt = if ($Default) { "$Label [$Default]" } else { $Label }
    while ($true) {
        if ($Secret) {
            $secure = Read-Host -Prompt $prompt -AsSecureString
            $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
        } else {
            $value = Read-Host -Prompt $prompt
        }
        if (-not $value) { $value = $Default }
        if ($value) { return $value }
        Write-Host 'A value is required.'
    }
}

function Prompt-YesNo {
    param(
        [string]$Name,
        [string]$Label,
        [string]$Default = 'No'
    )
    $envVal = [Environment]::GetEnvironmentVariable($Name)
    if ($envVal) {
        switch ($envVal.ToLower()) {
            { $_ -in 'y','yes' } { return 'Yes' }
            { $_ -in 'n','no' }  { return 'No' }
            default { throw "Invalid value for ${Name}: $envVal. Use Yes or No." }
        }
    }

    while ($true) {
        $value = Read-Host -Prompt "$Label [Yes/No, default $Default]"
        if (-not $value) { $value = $Default }
        switch ($value.ToLower()) {
            { $_ -in 'y','yes' } { return 'Yes' }
            { $_ -in 'n','no' }  { return 'No' }
            default { Write-Host 'Please enter Yes or No.' }
        }
    }
}

function Validate-Url {
    param(
        [string]$Url,
        [string]$Suffix = ''
    )
    if ($Url -notmatch '^https://') {
        Write-Host 'URL must start with https://'
        return $false
    }
    if ($Suffix -and -not $Url.EndsWith($Suffix)) {
        Write-Host "URL must end with $Suffix"
        return $false
    }
    return $true
}

function Prompt-Url {
    param(
        [string]$Name,
        [string]$Label,
        [string]$Default = '',
        [string]$Suffix = ''
    )
    $envVal = [Environment]::GetEnvironmentVariable($Name)
    if ($envVal) {
        if (-not (Validate-Url -Url $envVal -Suffix $Suffix)) { throw "Invalid URL for ${Name}: $envVal" }
        return $envVal
    }

    $prompt = if ($Default) { "$Label [$Default]" } else { $Label }
    while ($true) {
        $value = Read-Host -Prompt $prompt
        if (-not $value) { $value = $Default }
        if (-not $value) { Write-Host 'A value is required.'; continue }
        if (Validate-Url -Url $value -Suffix $Suffix) { return $value }
    }
}

function Truncate-Name {
    param([string]$Base, [string]$Suffix, [int]$Max = 120)
    $allowed = $Max - $Suffix.Length
    if ($allowed -lt 1) { return $Suffix.Substring(0, $Max) }
    return $Base.Substring(0, [Math]::Min($Base.Length, $allowed)) + $Suffix
}

function Invoke-Az {
    param([Parameter(ValueFromRemainingArguments)]$AzArgs)
    $stderr = $null
    $output = & az @AzArgs 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $stderr += $_.ToString() }
        else { $_ }
    }
    if ($LASTEXITCODE -ne 0) { throw "az command failed: $stderr $output" }
    return $output
}

function Invoke-AzJson {
    param([Parameter(ValueFromRemainingArguments)]$AzArgs)
    $raw = Invoke-Az @AzArgs --output json
    return ($raw -join "`n") | ConvertFrom-Json
}

function Invoke-AzRestJson {
    param(
        [string]$Method,
        [string]$Url,
        [string]$Body
    )
    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmpFile, $Body)
        $raw = Invoke-Az rest --method $Method --url $Url --headers 'Content-Type=application/json' --body "@$tmpFile" --output json
        return ($raw -join "`n") | ConvertFrom-Json
    } finally {
        Remove-Item -Path $tmpFile -ErrorAction SilentlyContinue
    }
}

function Invoke-AzRestVoid {
    param(
        [string]$Method,
        [string]$Url,
        [string]$Body
    )
    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmpFile, $Body)
        Invoke-Az rest --method $Method --url $Url --headers 'Content-Type=application/json' --body "@$tmpFile" | Out-Null
    } finally {
        Remove-Item -Path $tmpFile -ErrorAction SilentlyContinue
    }
}

# --- Collected state for error reporting ---
$script:State = @{}

trap {
    Write-Host "`nScript failed."
    Write-Host "`nCollected information so far:"
    Write-Host '============================'
    $script:State.GetEnumerator() | Sort-Object Name | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Value)"
    }
}

# --- Pre-flight checks ---

Write-Host 'Checking Azure login...'
$account = Invoke-AzJson account show
$TenantId = $account.tenantId
$script:State['TenantId'] = $TenantId

$SignedInUser = (Invoke-AzJson ad signed-in-user show).id
$GraphAppId = '00000003-0000-0000-c000-000000000000'

# --- Product selection ---

$Product = [Environment]::GetEnvironmentVariable('PRODUCT')
if ($Product) {
    $Product = switch ($Product.ToLower()) {
        { $_ -in '1','workbench' }          { 'workbench' }
        { $_ -in '2','connect' }            { 'connect' }
        { $_ -in '3','packagemanager','ppm' } { 'packagemanager' }
        default { throw "Invalid PRODUCT value: $Product" }
    }
} else {
    Write-Host ''
    Write-Host 'Select Posit product to configure:'
    Write-Host '  1) Posit Workbench'
    Write-Host '  2) Posit Connect'
    Write-Host '  3) Posit Package Manager'
    Write-Host ''
    while ($true) {
        $choice = Read-Host -Prompt 'Product [1/2/3]'
        $Product = switch ($choice) {
            '1' { 'workbench' }
            '2' { 'connect' }
            '3' { 'packagemanager' }
            default { $null }
        }
        if ($Product) { break }
        Write-Host 'Please enter 1, 2, or 3.'
    }
}
$script:State['Product'] = $Product

$ProductConfig = switch ($Product) {
    'workbench'      { @{ DefaultAppName = 'posit-workbench-oidc';        Label = 'Posit Workbench';        UrlExample = 'https://workbench.example.com' } }
    'connect'        { @{ DefaultAppName = 'posit-connect-oidc';          Label = 'Posit Connect';          UrlExample = 'https://connect.example.com' } }
    'packagemanager' { @{ DefaultAppName = 'posit-package-manager-oidc';  Label = 'Posit Package Manager';  UrlExample = 'https://packagemanager.example.com' } }
}

Write-Host ''
Write-Host "Configuring Entra ID for $($ProductConfig.Label)"
Write-Host '========================================'

if ($Product -eq 'workbench') {
    $WbMode = [Environment]::GetEnvironmentVariable('WB_MODE')
    if ($WbMode) {
        switch ($WbMode.ToLower()) {
            { $_ -in '1','oidc-scim','oidc+scim' } { $SkipOidc = 'No';  $CreateScim = 'Yes' }
            { $_ -in '2','oidc' }                   { $SkipOidc = 'No';  $CreateScim = 'No' }
            { $_ -in '3','scim' }                    { $SkipOidc = 'Yes'; $CreateScim = 'Yes' }
            default { throw "Invalid WB_MODE value: $WbMode. Use oidc+scim, oidc, or scim." }
        }
    } else {
        Write-Host ''
        Write-Host 'Select Workbench configuration mode:'
        Write-Host '  1) OIDC + SCIM provisioning'
        Write-Host '  2) OIDC only'
        Write-Host '  3) SCIM provisioning only'
        Write-Host ''
        while ($true) {
            $wbChoice = Read-Host -Prompt 'Mode [1/2/3]'
            switch ($wbChoice) {
                '1' { $SkipOidc = 'No';  $CreateScim = 'Yes'; break }
                '2' { $SkipOidc = 'No';  $CreateScim = 'No';  break }
                '3' { $SkipOidc = 'Yes'; $CreateScim = 'Yes'; break }
                default { Write-Host 'Please enter 1, 2, or 3.'; continue }
            }
            break
        }
    }
} else {
    $SkipOidc = 'No'
    $CreateScim = 'No'
}

if ($SkipOidc -ne 'Yes') {
    $AppName          = Prompt-Value -Name 'APP_NAME'           -Label 'OIDC app registration name'         -Default $ProductConfig.DefaultAppName
    $BaseUrl          = Prompt-Url   -Name 'BASE_URL'           -Label "$($ProductConfig.Label) base URL"    -Default $ProductConfig.UrlExample
    $script:State['AppName'] = $AppName
    $script:State['BaseUrl'] = $BaseUrl

    $RedirectSuffix = switch ($Product) {
        'workbench' { '/openid/callback' }
        default     { '/__login__/callback' }
    }
    $DefaultRedirect = "$($BaseUrl.TrimEnd('/'))$RedirectSuffix"

    $RedirectUri      = Prompt-Url   -Name 'REDIRECT_URI'       -Label 'OIDC redirect URI'                  -Default $DefaultRedirect -Suffix $RedirectSuffix
    $ClientSecretName = Prompt-Value -Name 'CLIENT_SECRET_NAME' -Label 'Client secret display name'         -Default "$AppName-secret"
    $SigninAudience   = Prompt-Value -Name 'SIGNIN_AUDIENCE'    -Label 'Sign-in audience: AzureADMyOrg, AzureADMultipleOrgs' -Default 'AzureADMyOrg'
    $IncludeGroups    = Prompt-YesNo -Name 'INCLUDE_GROUP_CLAIMS' -Label 'Include group claims in ID/access tokens?' -Default 'Yes'
    $GroupClaims      = Prompt-Value -Name 'GROUP_CLAIMS'       -Label 'Group claim mode: SecurityGroup, All, DirectoryRole, ApplicationGroup, None' -Default 'SecurityGroup'

    $GroupMembership = if ($IncludeGroups -eq 'Yes') { $GroupClaims } else { 'None' }

    # --- Create OIDC app registration ---

    Write-Host 'Creating OIDC app registration...'
    $appBody = @{
        displayName            = $AppName
        signInAudience         = $SigninAudience
        groupMembershipClaims  = $GroupMembership
        web = @{
            redirectUris = @($RedirectUri)
            implicitGrantSettings = @{
                enableIdTokenIssuance     = $true
                enableAccessTokenIssuance = $false
            }
        }
        optionalClaims = @{
            idToken = @(
                @{ name = 'email';              essential = $false }
                @{ name = 'preferred_username'; essential = $false }
            )
        }
    } | ConvertTo-Json -Depth 5 -Compress

    $appJson = Invoke-AzRestJson -Method POST -Url 'https://graph.microsoft.com/v1.0/applications' -Body $appBody

    $AppObjectId = $appJson.id
    $ClientId    = $appJson.appId
    $script:State['ClientId']    = $ClientId
    $script:State['AppObjectId'] = $AppObjectId

    # --- Add delegated permissions ---
    # Microsoft Graph delegated permission GUIDs:
    #   openid         = 37f7f235-527c-4136-accd-4a02d197296e
    #   email          = 64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0
    #   profile        = 14dad69e-099b-42c9-810b-d002981feec1
    #   offline_access = 7427e0e9-2fba-42fe-b0c0-848c9e6a818b
    #   User.Read      = e1fe6dd8-ba31-4d61-89e7-88639da4683d

    Write-Host 'Adding OpenID delegated permissions...'
    try {
        Invoke-Az ad app permission add --id $ClientId --api $GraphAppId --api-permissions `
            '37f7f235-527c-4136-accd-4a02d197296e=Scope' `
            '64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0=Scope' `
            '14dad69e-099b-42c9-810b-d002981feec1=Scope' `
            '7427e0e9-2fba-42fe-b0c0-848c9e6a818b=Scope' `
            'e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope' | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch 'already exist') { throw }
    }

    # --- Create client secret ---

    Write-Host 'Creating client secret...'
    $secretBody = @{ passwordCredential = @{ displayName = $ClientSecretName } } | ConvertTo-Json -Compress
    $secretJson = Invoke-AzRestJson -Method POST -Url "https://graph.microsoft.com/v1.0/applications/$AppObjectId/addPassword" -Body $secretBody

    $ClientSecret = $secretJson.secretText
    $script:State['ClientSecret'] = '***'

    # --- Add owner ---

    Write-Host 'Adding signed-in user as app owner...'
    $ownerBody = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$SignedInUser" } | ConvertTo-Json -Compress
    try {
        Invoke-AzRestVoid -Method POST -Url "https://graph.microsoft.com/v1.0/applications/$AppObjectId/owners/`$ref" -Body $ownerBody
    } catch { }

    # --- Create/ensure service principal ---

    Write-Host 'Creating/ensuring enterprise service principal...'
    try { Invoke-Az ad sp create --id $ClientId | Out-Null } catch { }
    for ($i = 1; $i -le 6; $i++) {
        try {
            $SpObjectId = (Invoke-AzJson ad sp show --id $ClientId).id
            break
        } catch {
            if ($i -eq 6) { throw "Timed out waiting for service principal for $ClientId to become available." }
            Start-Sleep -Seconds 5
        }
    }
    $script:State['SpObjectId'] = $SpObjectId

    try {
        Invoke-AzRestVoid -Method POST -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$SpObjectId/owners/`$ref" -Body $ownerBody
    } catch { }

    Write-Host 'Requiring user assignment on enterprise app...'
    $assignReqBody = @{ appRoleAssignmentRequired = $true } | ConvertTo-Json -Compress
    Invoke-AzRestVoid -Method PATCH -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$SpObjectId" -Body $assignReqBody

    Write-Host 'Assigning signed-in user to enterprise app...'
    $assignBody = @{
        principalId = $SignedInUser
        resourceId  = $SpObjectId
        appRoleId   = '00000000-0000-0000-0000-000000000000'
    } | ConvertTo-Json -Compress
    Invoke-AzRestVoid -Method POST -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$SpObjectId/appRoleAssignedTo" -Body $assignBody

} else {
    $BaseUrl = Prompt-Url -Name 'BASE_URL' -Label "$($ProductConfig.Label) base URL" -Default $ProductConfig.UrlExample
    $AppName = if ([Environment]::GetEnvironmentVariable('APP_NAME')) { [Environment]::GetEnvironmentVariable('APP_NAME') } else { $ProductConfig.DefaultAppName }
}

# --- SCIM (Workbench only) ---

$ScimOutput = ''
if ($CreateScim -eq 'Yes') {
    $DefaultScimAppName = Truncate-Name -Base $AppName -Suffix '-scim-provisioning' -Max 120
    $DefaultScimUrl     = "$($BaseUrl.TrimEnd('/'))/scim/v2"

    $ScimAppName = Prompt-Value -Name 'SCIM_APP_NAME' -Label 'SCIM enterprise app name'     -Default $DefaultScimAppName
    $ScimUrl     = Prompt-Url   -Name 'SCIM_URL'      -Label 'Workbench SCIM base URL'      -Default $DefaultScimUrl -Suffix '/scim/v2'

    Write-Host 'Testing SCIM endpoint reachability...'
    $scimReachable = $false
    try {
        $null = Invoke-WebRequest -Uri $ScimUrl -Method Head -TimeoutSec 10 -SkipCertificateCheck -ErrorAction Stop
        $scimReachable = $true
    } catch [System.Net.Http.HttpRequestException] {
        $scimReachable = $false
    } catch {
        $scimReachable = $true
    }
    if ($scimReachable) {
        Write-Host 'SCIM endpoint is reachable.'
    } else {
        Write-Host "WARNING: SCIM endpoint at $ScimUrl is not reachable from this environment."
        $scimConfirmed = Prompt-YesNo -Name 'SCIM_CONNECTIVITY_CONFIRMED' -Label 'Do you have connectivity between Azure and your Workbench instance handled via another avenue (e.g., VPN, private endpoint)?' -Default 'No'
        if ($scimConfirmed -ne 'Yes') {
            Write-Host 'SCIM provisioning requires network connectivity from Azure to your Workbench instance. Exiting.'
            exit 1
        }
    }

    $ScimToken   = Prompt-Value -Name 'SCIM_TOKEN'    -Label 'Workbench SCIM bearer token'   -Secret
    $StartScim   = Prompt-YesNo -Name 'START_SCIM'    -Label 'Start SCIM provisioning job now?' -Default 'No'

    Write-Host 'Creating non-gallery SCIM enterprise application from Microsoft template...'
    $scimTemplateId = '8adf8e6e-67b2-4cf2-a259-e3dc5476c621'
    $instantiateBody = @{ displayName = $ScimAppName } | ConvertTo-Json -Compress

    $scimAppJson = Invoke-AzRestJson -Method POST -Url "https://graph.microsoft.com/v1.0/applicationTemplates/$scimTemplateId/instantiate" -Body $instantiateBody

    $ScimSpId  = $scimAppJson.servicePrincipal.id
    $ScimAppId = $scimAppJson.application.appId
    $script:State['ScimSpId']  = $ScimSpId
    $script:State['ScimAppId'] = $ScimAppId

    if (-not $ScimSpId) {
        Write-Host 'SCIM application creation did not return a service principal ID.'
        Write-Host ($scimAppJson | ConvertTo-Json -Depth 5)
        exit 1
    }

    Write-Host 'Waiting for SCIM service principal to become available...'
    for ($i = 1; $i -le 12; $i++) {
        try {
            Invoke-Az ad sp show --id $ScimSpId --output none | Out-Null
            break
        } catch {
            if ($i -eq 12) { throw "Timed out waiting for service principal $ScimSpId to become available." }
            Start-Sleep -Seconds 5
        }
    }

    Write-Host 'Adding signed-in user as SCIM app owner...'
    $ScimAppObjectId = (Invoke-AzJson ad app show --id $ScimAppId).id
    try {
        Invoke-AzRestVoid -Method POST -Url "https://graph.microsoft.com/v1.0/applications/$ScimAppObjectId/owners/`$ref" -Body $ownerBody
    } catch { }
    try {
        Invoke-AzRestVoid -Method POST -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$ScimSpId/owners/`$ref" -Body $ownerBody
    } catch { }

    Write-Host 'Waiting for ownership to propagate...'
    Start-Sleep -Seconds 10

    Write-Host 'Creating SCIM provisioning job...'
    $jobJson = Invoke-AzRestJson -Method POST -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$ScimSpId/synchronization/jobs" -Body '{"templateId":"scim"}'

    $ScimJobId = $jobJson.id
    $script:State['ScimJobId'] = $ScimJobId

    if (-not $ScimJobId) {
        Write-Host 'SCIM provisioning job creation did not return a job ID.'
        Write-Host ($jobJson | ConvertTo-Json -Depth 5)
        exit 1
    }

    Write-Host 'Saving SCIM endpoint and token...'
    $secretsBody = @{
        value = @(
            @{ key = 'BaseAddress'; value = $ScimUrl }
            @{ key = 'SecretToken'; value = $ScimToken }
        )
    } | ConvertTo-Json -Depth 3 -Compress

    Invoke-AzRestVoid -Method PUT -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$ScimSpId/synchronization/secrets" -Body $secretsBody

    if ($StartScim -eq 'Yes') {
        Write-Host 'Starting SCIM provisioning job...'
        Invoke-Az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$ScimSpId/synchronization/jobs/$ScimJobId/start" | Out-Null
    }

    $ScimOutput = @"

# SCIM Enterprise App:
#   Display name:        $ScimAppName
#   App/client ID:       $ScimAppId
#   Service principal:   $ScimSpId
#   Provisioning job ID: $ScimJobId
#   SCIM URL:            $ScimUrl
"@
}

# --- Output emit functions ---

function Emit-WorkbenchCommands {
    Write-Host @"
# Append OIDC settings to rserver.conf
cat >> /etc/rstudio/rserver.conf <<'RSERVER'

# --- Entra ID OpenID Connect ---
auth-openid=1
auth-openid-issuer=$Issuer
auth-openid-username-claim=preferred_username
RSERVER

# Create client credentials file
cat > /etc/rstudio/openid-client-secret <<'SECRET'
client-id=$ClientId
client-secret=$ClientSecret
SECRET
chmod 0600 /etc/rstudio/openid-client-secret

# Restart Workbench
sudo rstudio-server restart
"@
}

function Emit-ConnectCommands {
    $groupsLines = if ($IncludeGroups -eq 'Yes') { "`nGroupsAutoProvision = true`nGroupsClaim = `"groups`"" } else { '' }
    Write-Host @"
# Change auth provider from password to oauth2
sudo sed -i 's/^Provider = "password"/Provider = "oauth2"/' /etc/rstudio-connect/rstudio-connect.gcfg

# Append OAuth2 settings
cat >> /etc/rstudio-connect/rstudio-connect.gcfg <<'GCFG'

[OAuth2]
ClientId = "$ClientId"
ClientSecret = "$ClientSecret"
OpenIDConnectIssuer = "$Issuer"
RequireUsernameClaim = true
UsernameClaim = "preferred_username"${groupsLines}
GCFG

# Restart Connect
sudo systemctl restart rstudio-connect
"@
}

function Emit-PackageManagerCommands {
    Write-Host @"
# Set the server address for OIDC callback support
sudo sed -i 's|^; Address = "http://posit-connect.example.com"|Address = "$BaseUrl"|' /etc/rstudio-pm/rstudio-pm.gcfg

# Append OpenID Connect settings
cat >> /etc/rstudio-pm/rstudio-pm.gcfg <<'GCFG'

[OpenIDConnect]
Issuer = "$Issuer"
ClientId = "$ClientId"
ClientSecret = "$ClientSecret"
GCFG

# Restart Package Manager
sudo systemctl restart rstudio-pm
"@
}

# --- Output configuration commands ---

$Issuer = "https://login.microsoftonline.com/$TenantId/v2.0"

if ($SkipOidc -ne 'Yes') {
    Write-Host @"

=== Entra ID registration complete for $($ProductConfig.Label) ===

Tenant ID:             $TenantId
Client ID:             $ClientId
Client secret:         $ClientSecret
Redirect URI:          $RedirectUri
Issuer:                $Issuer
Enterprise App SP ID:  $SpObjectId
$ScimOutput
Run the following commands on your $($ProductConfig.Label) server to configure OIDC:
==========================================================================

"@

    switch ($Product) {
        'workbench'      { Emit-WorkbenchCommands }
        'connect'        { Emit-ConnectCommands }
        'packagemanager' { Emit-PackageManagerCommands }
    }
} else {
    Write-Host @"

=== SCIM-only configuration complete for $($ProductConfig.Label) ===

Tenant ID: $TenantId
$ScimOutput
"@
}
