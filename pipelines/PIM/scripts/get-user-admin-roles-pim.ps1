param (
    [string]$GraphClientId,    # Microsoft Graph API Client ID
    [string]$GraphTenantId,    # Microsoft Entra ID (Azure AD) Tenant ID
    [string]$UserEmail         # Email address of the user we are checking
)

# Retrieve the client secret from the environment variable
$GraphClientSecret = $env:GRAPH_CLIENT_SECRET

# Validate input parameters before proceeding
if (-not $GraphClientId -or -not $GraphTenantId -or -not $GraphClientSecret -or -not $UserEmail) {
    Write-Host "ERROR: Missing required parameters!" -ForegroundColor Red
    exit 1
}

# --------------------------------
# Step 1: Authenticate with Microsoft Graph API
# --------------------------------
try {
    $tokenUrl = "https://login.microsoftonline.com/$GraphTenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $GraphClientId
        scope        = "https://graph.microsoft.com/.default"
        client_secret = $GraphClientSecret
        grant_type    = "client_credentials"
    }
    
    # Request access token
    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUrl -ContentType "application/x-www-form-urlencoded" -Body $body
    $accessToken = $tokenResponse.access_token
}
catch {
    Write-Host "ERROR: Authentication to Microsoft Graph failed. $_" -ForegroundColor Red
    exit 1
}

# Set authorization headers for Graph API requests
$headers = @{
    Authorization = "Bearer $accessToken"
    Accept        = "application/json"
}

# --------------------------------
# Step 2: Fetch the User ID from Email
# --------------------------------
Write-Host "--------------------------------"
Write-Host "Fetching user ID for: $UserEmail"
Write-Host "--------------------------------"

try {
    $user = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$UserEmail" -Headers $headers -Method Get
    $userId = $user.id  # Extract User ID from response
}
catch {
    Write-Host "ERROR: Unable to retrieve user details. $_" -ForegroundColor Red
    exit 1
}

# --------------------------------
# Step 3: Fetch PIM Admin Roles using Graph API
# --------------------------------
Write-Host "--------------------------------"
Write-Host "Fetching PIM Admin Roles for user: $UserEmail"
Write-Host "--------------------------------"

$adminRoles = @()
$uri = "https://graph.microsoft.com/beta/roleManagement/directory/roleEligibilitySchedules?`$filter=principalId eq '$userId'" 

try {
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    if ($response -and $response.value) {
        $adminRoles = $response.value
    }
} catch {
    Write-Host "ERROR: Unable to retrieve PIM Admin Roles. $_" -ForegroundColor Red
}

# Fetch role names
$roleDefinitions = @{}
$roleUri = "https://graph.microsoft.com/beta/roleManagement/directory/roleDefinitions"
try {
    $roleResponse = Invoke-RestMethod -Uri $roleUri -Headers $headers -Method Get
    if ($roleResponse -and $roleResponse.value) {
        foreach ($role in $roleResponse.value) {
            $roleDefinitions[$role.id] = $role.displayName
        }
    }
} catch {
    Write-Host "ERROR: Unable to retrieve Role Definitions. $_" -ForegroundColor Red
}

# --------------------------------
# Step 4: Display PIM Admin Roles for the User
# --------------------------------
Write-Host "Total PIM Admin Roles found: $(($adminRoles | Measure-Object).Count)"

if ($adminRoles.Count -gt 0) {
    Write-Host "Role Name                                    | Role ID"
    Write-Host "---------------------------------------------|--------------------------------"

    foreach ($role in $adminRoles) {
        if ($roleDefinitions.ContainsKey($role.roleDefinitionId)) {
            $roleName = $roleDefinitions[$role.roleDefinitionId]
        } else {
            $roleName = "Unknown Role"
        }

        Write-Host ("{0,-45} | {1}" -f $roleName, $role.roleDefinitionId)
    }
} else {
    Write-Host "User has NO PIM Admin Roles."
}
