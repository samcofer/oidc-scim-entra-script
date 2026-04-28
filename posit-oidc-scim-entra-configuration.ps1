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

$PositLogoPngB64 = "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"

function Set-AppLogo {
    param([string]$AppObjectId)
    Write-Host 'Setting application logo...'
    $logoBytes = [Convert]::FromBase64String($PositLogoPngB64)
    $token = (Invoke-AzJson account get-access-token --resource https://graph.microsoft.com).accessToken
    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'image/png'
    }
    try {
        Invoke-RestMethod -Method Put `
            -Uri "https://graph.microsoft.com/v1.0/applications/$AppObjectId/logo" `
            -Headers $headers `
            -Body $logoBytes | Out-Null
        Write-Host 'Application logo set.'
    } catch {
        Write-Host 'WARNING: Failed to set application logo (non-fatal).'
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
$GraphSpId = (Invoke-AzJson ad sp show --id $GraphAppId).id
$ScimTemplateId = '8adf8e6e-67b2-4cf2-a259-e3dc5476c621'
$ownerBody = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$SignedInUser" } | ConvertTo-Json -Compress

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

# --- Workbench mode pre-check (needed before auth protocol selection) ---
$SkipOidc = 'No'
$CreateScim = 'No'
$WbModeScimOnly = 'No'

if ($Product -eq 'workbench') {
    $WbMode = [Environment]::GetEnvironmentVariable('WB_MODE')
    if ($WbMode -and $WbMode.ToLower() -in '3','scim') {
        $WbModeScimOnly = 'Yes'
    }
}

# --- Auth protocol selection ---
if ($Product -eq 'packagemanager') {
    $AuthProtocol = 'oidc'
} elseif ($WbModeScimOnly -eq 'Yes') {
    $AuthProtocol = 'scim-only'
} else {
    $AuthProtocol = [Environment]::GetEnvironmentVariable('AUTH_PROTOCOL')
    if ($AuthProtocol) {
        $AuthProtocol = switch ($AuthProtocol.ToLower()) {
            { $_ -in '1','oidc' } { 'oidc' }
            { $_ -in '2','saml' } { 'saml' }
            default { throw "Invalid AUTH_PROTOCOL value: $AuthProtocol. Use oidc or saml." }
        }
    } else {
        Write-Host ''
        Write-Host 'Select authentication protocol:'
        Write-Host '  1) OpenID Connect (OIDC)'
        Write-Host '  2) SAML'
        Write-Host ''
        while ($true) {
            $protoChoice = Read-Host -Prompt 'Protocol [1/2]'
            $AuthProtocol = switch ($protoChoice) {
                '1' { 'oidc' }
                '2' { 'saml' }
                default { $null }
            }
            if ($AuthProtocol) { break }
            Write-Host 'Please enter 1 or 2.'
        }
    }
}
$script:State['AuthProtocol'] = $AuthProtocol

$defaultAppName = if ($Product -eq 'workbench' -and $AuthProtocol -eq 'scim-only') { 'posit-workbench-scim' } elseif ($Product -eq 'workbench') { "posit-workbench-$AuthProtocol" } elseif ($Product -eq 'connect') { "posit-connect-$AuthProtocol" } else { 'posit-package-manager-oidc' }
$ProductConfig = switch ($Product) {
    'workbench'      { @{ DefaultAppName = $defaultAppName;  Label = 'Posit Workbench';        UrlExample = 'https://workbench.example.com' } }
    'connect'        { @{ DefaultAppName = $defaultAppName;  Label = 'Posit Connect';          UrlExample = 'https://connect.example.com' } }
    'packagemanager' { @{ DefaultAppName = $defaultAppName;  Label = 'Posit Package Manager';  UrlExample = 'https://packagemanager.example.com' } }
}

Write-Host ''
Write-Host "Configuring Entra ID for $($ProductConfig.Label) ($AuthProtocol)"
Write-Host '========================================'

if ($Product -eq 'workbench') {
    if ($WbMode) {
        switch ($WbMode.ToLower()) {
            { $_ -in '1','oidc-scim','oidc+scim','saml+scim','saml-scim' } { $SkipOidc = 'No';  $CreateScim = 'Yes' }
            { $_ -in '2','oidc','saml' }                                    { $SkipOidc = 'No';  $CreateScim = 'No' }
            { $_ -in '3','scim' }                                            { $SkipOidc = 'Yes'; $CreateScim = 'Yes' }
            default { throw "Invalid WB_MODE value: $WbMode. Use oidc+scim, saml+scim, oidc, saml, or scim." }
        }
    } else {
        $authLabel = $AuthProtocol.ToUpper()
        Write-Host ''
        Write-Host 'Select Workbench configuration mode:'
        Write-Host "  1) $authLabel + SCIM provisioning"
        Write-Host "  2) $authLabel only"
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
}

if ($SkipOidc -ne 'Yes') {
    $AppName          = Prompt-Value -Name 'APP_NAME'           -Label 'App registration name'              -Default $ProductConfig.DefaultAppName
    $BaseUrl          = Prompt-Url   -Name 'BASE_URL'           -Label "$($ProductConfig.Label) base URL"    -Default $ProductConfig.UrlExample
    $script:State['AppName'] = $AppName
    $script:State['BaseUrl'] = $BaseUrl

    # --- Common prompts ---
    $SigninAudience   = Prompt-Value -Name 'SIGNIN_AUDIENCE'    -Label 'Sign-in audience: AzureADMyOrg, AzureADMultipleOrgs' -Default 'AzureADMyOrg'
    $IncludeGroups    = Prompt-YesNo -Name 'INCLUDE_GROUP_CLAIMS' -Label 'Include group claims in ID/access tokens?' -Default 'Yes'
    $GroupClaims      = Prompt-Value -Name 'GROUP_CLAIMS'       -Label 'Group claim mode: SecurityGroup, All, DirectoryRole, ApplicationGroup, None' -Default 'SecurityGroup'

    $GroupMembership = if ($IncludeGroups -eq 'Yes') { $GroupClaims } else { 'None' }

    # --- OIDC-specific prompts ---
    if ($AuthProtocol -eq 'oidc') {
        $RedirectSuffix = switch ($Product) {
            'workbench' { '/openid/callback' }
            default     { '/__login__/callback' }
        }
        $DefaultRedirect = "$($BaseUrl.TrimEnd('/'))$RedirectSuffix"

        $RedirectUri      = Prompt-Url   -Name 'REDIRECT_URI'       -Label 'OIDC redirect URI'                  -Default $DefaultRedirect -Suffix $RedirectSuffix
        $ClientSecretName = Prompt-Value -Name 'CLIENT_SECRET_NAME' -Label 'Client secret display name'         -Default "$AppName-secret"
    }

    # --- SAML-specific computed values (ACS URL only; entity ID set after app creation) ---
    if ($AuthProtocol -eq 'saml') {
        $SamlAcsUrl = switch ($Product) {
            'workbench' { "$($BaseUrl.TrimEnd('/'))/saml/acs" }
            'connect'   { "$($BaseUrl.TrimEnd('/'))/__login__/saml/acs" }
        }
    }

    # --- JIT provisioning prompt (Workbench only) ---
    if ($Product -eq 'workbench') {
        $EnableJit = Prompt-YesNo -Name 'ENABLE_JIT' -Label 'Enable JIT (Just-In-Time) user provisioning?' -Default 'No'
    }

    # --- Collect SCIM prompts early for unified mode ---
    if ($CreateScim -eq 'Yes') {
        $DefaultScimUrl = "$($BaseUrl.TrimEnd('/'))/scim/v2"
        $ScimUrl = Prompt-Url -Name 'SCIM_URL' -Label 'Workbench SCIM base URL' -Default $DefaultScimUrl -Suffix '/scim/v2'

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
                Write-Host 'Skipping SCIM provisioning. SCIM requires network connectivity from Azure to your Workbench instance.'
                $CreateScim = 'No'
            }
        }

        if ($CreateScim -eq 'Yes') {
            $ScimToken = Prompt-Value -Name 'SCIM_TOKEN' -Label 'Workbench SCIM bearer token' -Secret
            $StartScim = Prompt-YesNo -Name 'START_SCIM' -Label 'Start SCIM provisioning job now?' -Default 'No'
            $EnableScimGroups = Prompt-YesNo -Name 'ENABLE_SCIM_GROUPS' -Label 'Enable SCIM group provisioning?' -Default 'Yes'
        }
    }

    # --- Create app registration / enterprise app ---
    if ($AuthProtocol -eq 'saml' -or $CreateScim -eq 'Yes') {
        # SAML and SCIM both require template instantiation for enterprise app
        Write-Host 'Creating enterprise application from Microsoft template...'
        $instantiateBody = @{ displayName = $AppName } | ConvertTo-Json -Compress
        $templateJson = Invoke-AzRestJson -Method POST -Url "https://graph.microsoft.com/v1.0/applicationTemplates/$ScimTemplateId/instantiate" -Body $instantiateBody

        $SpObjectId = $templateJson.servicePrincipal.id
        $ClientId   = $templateJson.application.appId

        if (-not $SpObjectId) {
            Write-Host 'Template instantiation did not return a service principal ID.'
            Write-Host ($templateJson | ConvertTo-Json -Depth 5)
            exit 1
        }

        Write-Host 'Waiting for service principal to become available...'
        for ($i = 1; $i -le 12; $i++) {
            try {
                Invoke-Az ad sp show --id $SpObjectId --output none | Out-Null
                break
            } catch {
                if ($i -eq 12) { throw "Timed out waiting for service principal $SpObjectId to become available." }
                Start-Sleep -Seconds 5
            }
        }

        $AppObjectId = (Invoke-AzJson ad app show --id $ClientId).id

        if ($AuthProtocol -eq 'saml') {
            $SamlEntityId = "api://$ClientId"

            Write-Host 'Configuring SAML on app registration...'
            $patchBody = @{
                identifierUris        = @($SamlEntityId)
                groupMembershipClaims = $GroupMembership
                web = @{
                    redirectUris = @($SamlAcsUrl)
                }
            } | ConvertTo-Json -Depth 5 -Compress
            Invoke-AzRestVoid -Method PATCH -Url "https://graph.microsoft.com/v1.0/applications/$AppObjectId" -Body $patchBody

            Write-Host 'Enabling SAML single sign-on on enterprise app...'
            $samlBody = @{ preferredSingleSignOnMode = 'saml' } | ConvertTo-Json -Compress
            Invoke-AzRestVoid -Method PATCH -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$SpObjectId" -Body $samlBody

            $SamlMetadataUrl = "https://login.microsoftonline.com/$TenantId/federationmetadata/2007-06/federationmetadata.xml?appid=$ClientId"
        } else {
            Write-Host 'Configuring app registration with OIDC settings...'
            $patchBody = @{
                signInAudience        = $SigninAudience
                groupMembershipClaims = $GroupMembership
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
            Invoke-AzRestVoid -Method PATCH -Url "https://graph.microsoft.com/v1.0/applications/$AppObjectId" -Body $patchBody
        }
    } else {
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
    }

    $script:State['ClientId']    = $ClientId
    $script:State['AppObjectId'] = $AppObjectId

    Set-AppLogo -AppObjectId $AppObjectId

    # --- OIDC-specific: delegated permissions + client secret ---
    if ($AuthProtocol -eq 'oidc') {
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

        Write-Host 'Creating client secret...'
        $secretBody = @{ passwordCredential = @{ displayName = $ClientSecretName } } | ConvertTo-Json -Compress
        $secretJson = Invoke-AzRestJson -Method POST -Url "https://graph.microsoft.com/v1.0/applications/$AppObjectId/addPassword" -Body $secretBody
        $ClientSecret = $secretJson.secretText
        $script:State['ClientSecret'] = '***'
    }

    Write-Host 'Adding signed-in user as app owner...'
    try {
        Invoke-AzRestVoid -Method POST -Url "https://graph.microsoft.com/v1.0/applications/$AppObjectId/owners/`$ref" -Body $ownerBody
    } catch { }

    if (-not $SpObjectId) {
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
    }
    $script:State['SpObjectId'] = $SpObjectId

    try {
        Invoke-AzRestVoid -Method POST -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$SpObjectId/owners/`$ref" -Body $ownerBody
    } catch { }

    # --- OIDC-specific: admin consent ---
    if ($AuthProtocol -eq 'oidc') {
        Write-Host 'Granting admin consent for delegated permissions...'
        $consentBody = @{
            clientId    = $SpObjectId
            consentType = 'AllPrincipals'
            resourceId  = $GraphSpId
            scope       = 'email offline_access openid profile User.Read'
        } | ConvertTo-Json -Compress
        Invoke-AzRestJson -Method POST -Url 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -Body $consentBody | Out-Null
    }

    Write-Host 'Requiring user assignment on enterprise app...'
    $assignReqBody = @{ appRoleAssignmentRequired = $true } | ConvertTo-Json -Compress
    Invoke-AzRestVoid -Method PATCH -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$SpObjectId" -Body $assignReqBody

    Write-Host 'Assigning signed-in user to enterprise app...'
    $spInfo = Invoke-AzJson rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$SpObjectId"
    $appRoleId = ($spInfo.appRoles | Where-Object { $_.isEnabled } | Select-Object -First 1).id
    if (-not $appRoleId) { $appRoleId = '00000000-0000-0000-0000-000000000000' }
    $assignBody = @{
        principalId = $SignedInUser
        resourceId  = $SpObjectId
        appRoleId   = $appRoleId
    } | ConvertTo-Json -Compress
    Invoke-AzRestVoid -Method POST -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$SpObjectId/appRoleAssignedTo" -Body $assignBody

} else {
    $BaseUrl = Prompt-Url -Name 'BASE_URL' -Label "$($ProductConfig.Label) base URL" -Default $ProductConfig.UrlExample
    $AppName = if ([Environment]::GetEnvironmentVariable('APP_NAME')) { [Environment]::GetEnvironmentVariable('APP_NAME') } else { $ProductConfig.DefaultAppName }
}

# --- SCIM provisioning (Workbench only) ---

$ScimOutput = ''
if ($CreateScim -eq 'Yes') {
    if ($SkipOidc -eq 'Yes') {
        # Mode 3 (SCIM only): standalone SCIM app
        $DefaultScimAppName = Truncate-Name -Base $AppName -Suffix '-scim-provisioning' -Max 120
        $DefaultScimUrl     = "$($BaseUrl.TrimEnd('/'))/scim/v2"

        $ScimAppName = Prompt-Value -Name 'SCIM_APP_NAME' -Label 'SCIM enterprise app name' -Default $DefaultScimAppName
        $ScimUrl     = Prompt-Url   -Name 'SCIM_URL'      -Label 'Workbench SCIM base URL'  -Default $DefaultScimUrl -Suffix '/scim/v2'

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
                Write-Host 'Skipping SCIM provisioning. SCIM requires network connectivity from Azure to your Workbench instance.'
                $CreateScim = 'No'
            }
        }
    }
}

if ($CreateScim -eq 'Yes') {
    if ($SkipOidc -eq 'Yes') {
        # Mode 3: collect remaining prompts and create standalone SCIM app
        $ScimToken = Prompt-Value -Name 'SCIM_TOKEN' -Label 'Workbench SCIM bearer token' -Secret
        $StartScim = Prompt-YesNo -Name 'START_SCIM' -Label 'Start SCIM provisioning job now?' -Default 'No'
        $EnableScimGroups = Prompt-YesNo -Name 'ENABLE_SCIM_GROUPS' -Label 'Enable SCIM group provisioning?' -Default 'Yes'

        Write-Host 'Creating SCIM enterprise application from Microsoft template...'
        $instantiateBody = @{ displayName = $ScimAppName } | ConvertTo-Json -Compress
        $scimAppJson = Invoke-AzRestJson -Method POST -Url "https://graph.microsoft.com/v1.0/applicationTemplates/$ScimTemplateId/instantiate" -Body $instantiateBody

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
        Set-AppLogo -AppObjectId $ScimAppObjectId
        try {
            Invoke-AzRestVoid -Method POST -Url "https://graph.microsoft.com/v1.0/applications/$ScimAppObjectId/owners/`$ref" -Body $ownerBody
        } catch { }
        try {
            Invoke-AzRestVoid -Method POST -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$ScimSpId/owners/`$ref" -Body $ownerBody
        } catch { }
    } else {
        # Mode 1 (OIDC+SCIM unified): reuse the already-created SP
        $ScimSpId = $SpObjectId
    }

    Write-Host 'Waiting for provisioning readiness...'
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

    if ($EnableScimGroups -eq 'Yes') {
        Write-Host 'Enabling SCIM group provisioning...'
        $schemaJson = Invoke-AzJson rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$ScimSpId/synchronization/jobs/$ScimJobId/schema"
        foreach ($rule in $schemaJson.synchronizationRules) {
            foreach ($mapping in $rule.objectMappings) {
                if ($mapping.sourceObjectName -eq 'Group') {
                    $mapping.enabled = $true
                }
            }
        }
        $updatedSchema = $schemaJson | ConvertTo-Json -Depth 20 -Compress
        Invoke-AzRestVoid -Method PUT -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$ScimSpId/synchronization/jobs/$ScimJobId/schema" -Body $updatedSchema
    }

    if ($StartScim -eq 'Yes') {
        Write-Host 'Starting SCIM provisioning job...'
        Invoke-Az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$ScimSpId/synchronization/jobs/$ScimJobId/start" | Out-Null
    }

    if ($SkipOidc -ne 'Yes') {
        $ScimOutput = @"

# SCIM Provisioning (same app):
#   Provisioning job ID: $ScimJobId
#   SCIM URL:            $ScimUrl
"@
    } else {
        $ScimOutput = @"

# SCIM Enterprise App:
#   Display name:        $ScimAppName
#   App/client ID:       $ScimAppId
#   Service principal:   $ScimSpId
#   Provisioning job ID: $ScimJobId
#   SCIM URL:            $ScimUrl
#   Enterprise App:      https://portal.azure.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/$ScimSpId/appId/$ScimAppId
"@
    }
}

# --- Output emit functions ---

function Emit-WorkbenchCommands {
    $jitLines = ''
    if ($EnableJit -eq 'Yes') {
        $jitLines = "`nuser-provisioning-enabled=1`nuser-provisioning-register-on-first-login=1"
        if ($IncludeGroups -eq 'Yes') {
            $jitLines += "`nauth-openid-groups-claim=groups"
        }
    }
    $scimLines = ''
    if ($CreateScim -eq 'Yes') {
        if ($EnableJit -ne 'Yes') {
            $scimLines = "`nuser-provisioning-enabled=1"
        }
        if ($EnableScimGroups -eq 'Yes') {
            $scimLines += "`ngroup-provisioning-start-gid=1000"
        }
    }
    Write-Host @"
# Append OIDC settings to rserver.conf
cat >> /etc/rstudio/rserver.conf <<'RSERVER'

# --- Entra ID OpenID Connect ---
auth-openid=1
auth-openid-issuer=$Issuer
auth-openid-username-claim=preferred_username${jitLines}${scimLines}
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

function Emit-ConnectSamlCommands {
    $groupsLine = if ($IncludeGroups -eq 'Yes') { "`nGroupsAutoProvision = true" } else { '' }
    Write-Host @"
# Set auth provider to saml
sudo sed -i 's/^Provider = "password"/Provider = "saml"/' /etc/rstudio-connect/rstudio-connect.gcfg

# Append SAML settings
cat >> /etc/rstudio-connect/rstudio-connect.gcfg <<'GCFG'

[SAML]
IdPMetaDataURL = "$SamlMetadataUrl"
IdPAttributeProfile = azure
IdPSingleSignOnPostBinding = true${groupsLine}
GCFG

# Restart Connect
sudo systemctl restart rstudio-connect
"@
}

function Emit-WorkbenchSamlCommands {
    $jitLines = ''
    if ($EnableJit -eq 'Yes') {
        $jitLines = "`nuser-provisioning-enabled=1`nuser-provisioning-register-on-first-login=1"
        if ($IncludeGroups -eq 'Yes') {
            $jitLines += "`nauth-saml-sp-attribute-groups=http://schemas.microsoft.com/ws/2008/06/identity/claims/groups"
        }
    }
    $scimLines = ''
    if ($CreateScim -eq 'Yes') {
        if ($EnableJit -ne 'Yes') {
            $scimLines = "`nuser-provisioning-enabled=1"
        }
        if ($EnableScimGroups -eq 'Yes') {
            $scimLines += "`ngroup-provisioning-start-gid=1000"
        }
    }
    Write-Host @"
# Append SAML settings to rserver.conf
cat >> /etc/rstudio/rserver.conf <<'RSERVER'

# --- Entra ID SAML ---
auth-saml=1
auth-saml-metadata-url=$SamlMetadataUrl
auth-saml-sp-name-id-format=emailaddress
auth-saml-sp-attribute-username=NameID${jitLines}${scimLines}
RSERVER

# Restart Workbench
sudo rstudio-server restart
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
    if ($AuthProtocol -eq 'saml') {
        Write-Host @"

=== Entra ID SAML registration complete for $($ProductConfig.Label) ===

Tenant ID:             $TenantId
Client/App ID:         $ClientId
Entity ID:             $SamlEntityId
ACS URL:               $SamlAcsUrl
Metadata URL:          $SamlMetadataUrl
Enterprise App SP ID:  $SpObjectId

App Registration:      https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$ClientId
Enterprise App:        https://portal.azure.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/$SpObjectId/appId/$ClientId
$ScimOutput
Run the following commands on your $($ProductConfig.Label) server to configure SAML:
==========================================================================

"@
    } else {
        Write-Host @"

=== Entra ID OIDC registration complete for $($ProductConfig.Label) ===

Tenant ID:             $TenantId
Client ID:             $ClientId
Client secret:         $ClientSecret
Redirect URI:          $RedirectUri
Issuer:                $Issuer
Enterprise App SP ID:  $SpObjectId

App Registration:      https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$ClientId
Enterprise App:        https://portal.azure.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/$SpObjectId/appId/$ClientId
$ScimOutput
Run the following commands on your $($ProductConfig.Label) server to configure OIDC:
==========================================================================

"@
    }

    switch ($Product) {
        'workbench' {
            if ($AuthProtocol -eq 'saml') { Emit-WorkbenchSamlCommands }
            else { Emit-WorkbenchCommands }
        }
        'connect' {
            if ($AuthProtocol -eq 'saml') { Emit-ConnectSamlCommands }
            else { Emit-ConnectCommands }
        }
        'packagemanager' { Emit-PackageManagerCommands }
    }
} else {
    $scimRserverLines = 'user-provisioning-enabled=1'
    if ($EnableScimGroups -eq 'Yes') {
        $scimRserverLines += "`ngroup-provisioning-start-gid=1000"
    }

    Write-Host @"

=== SCIM-only configuration complete for $($ProductConfig.Label) ===

Tenant ID: $TenantId
$ScimOutput
Run the following commands on your $($ProductConfig.Label) server to enable SCIM provisioning:
==========================================================================

# Append SCIM provisioning settings to rserver.conf
cat >> /etc/rstudio/rserver.conf <<'RSERVER'

$scimRserverLines
RSERVER

# Restart Workbench
sudo rstudio-server restart
"@
}
