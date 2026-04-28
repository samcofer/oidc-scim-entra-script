# Step 6: PowerShell Script Mirror

## Principle
Every change to the bash script has a corresponding change in the PS1 script. The PS1 script follows the same structure, prompts, variable names, and logic — only the language idioms differ per CLAUDE.md rules.

## Changes to Mirror

### 1. Auth Protocol Selection
```powershell
$AuthProtocol = [Environment]::GetEnvironmentVariable('AUTH_PROTOCOL')
if ($Product -eq 'packagemanager') {
    $AuthProtocol = 'oidc'
} elseif ($AuthProtocol) {
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
        $choice = Read-Host -Prompt 'Protocol [1/2]'
        $AuthProtocol = switch ($choice) {
            '1' { 'oidc' }
            '2' { 'saml' }
            default { $null }
        }
        if ($AuthProtocol) { break }
        Write-Host 'Please enter 1 or 2.'
    }
}
$script:State['AuthProtocol'] = $AuthProtocol
```

### 2. Default App Name
```powershell
$ProductConfig = switch ($Product) {
    'workbench'      { @{ DefaultAppName = "posit-workbench-$AuthProtocol"; ... } }
    'connect'        { @{ DefaultAppName = "posit-connect-$AuthProtocol"; ... } }
    'packagemanager' { @{ DefaultAppName = 'posit-package-manager-oidc'; ... } }
}
```

### 3. SAML App Creation Path
When `$AuthProtocol -eq 'saml'`:
- Skip: REDIRECT_URI prompt, CLIENT_SECRET_NAME prompt
- Skip: `addPassword`, `permission add`, `oauth2PermissionGrants`
- Add: template instantiation, PATCH SP for SAML mode, PATCH app for identifierUris

### 4. SAML Config Output Functions
```powershell
function Emit-ConnectSamlCommands { ... }
function Emit-WorkbenchSamlCommands { ... }
```

### 5. JIT Prompt
```powershell
if ($Product -eq 'workbench' -and $SkipOidc -ne 'Yes') {
    $EnableJit = Prompt-YesNo -Name 'ENABLE_JIT' -Label 'Enable JIT (Just-In-Time) user provisioning?' -Default 'No'
}
```

### 6. SCIM Group Provisioning
```powershell
if ($CreateScim -eq 'Yes') {
    $EnableScimGroups = Prompt-YesNo -Name 'ENABLE_SCIM_GROUPS' -Label 'Enable SCIM group provisioning?' -Default 'Yes'
}
```

Schema update uses `Invoke-AzRestJson` GET then `Invoke-AzRestVoid` PUT with temp file for the large schema body.

### 7. PS1-Specific Considerations
- JSON body construction via hashtables + `ConvertTo-Json -Depth 5 -Compress` + temp files
- Schema manipulation: `$schema.synchronizationRules | ForEach-Object { $_.objectMappings | Where-Object { $_.sourceObjectName -eq 'Group' } | ForEach-Object { $_.enabled = $true } }`
- `--output json` (long form, not `-o json`)
- `$AzArgs` parameter name in Invoke-Az

## Testing
PS1 is tested from WSL via:
```bash
PWSH="/mnt/c/Users/samco/AppData/Local/Microsoft/WindowsApps/Microsoft.PowerShell_8wekyb3d8bbwe/pwsh.exe"
# Copy script to Windows filesystem first
cp posit-oidc-scim-entra-configuration.ps1 /mnt/c/Users/samco/
"$PWSH" -NoProfile -Command '
$env:PATH += ";C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin"
$env:PRODUCT = "connect"
$env:AUTH_PROTOCOL = "saml"
$env:APP_NAME = "ps-test-connect-saml"
$env:BASE_URL = "https://connect.test.example.com"
$env:SIGNIN_AUDIENCE = "AzureADMyOrg"
$env:INCLUDE_GROUP_CLAIMS = "Yes"
$env:GROUP_CLAIMS = "SecurityGroup"
& "C:\Users\samco\posit-oidc-scim-entra-configuration.ps1"
'
```
