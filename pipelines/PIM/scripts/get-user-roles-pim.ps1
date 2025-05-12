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
# Step 2: Fetch all PIM-managed groups
# --------------------------------
Write-Host "--------------------------------"
Write-Host "Fetching all PIM-managed groups..."
Write-Host "--------------------------------"

$pimGroups = @()
$uri = "https://graph.microsoft.com/beta/privilegedAccess/aadGroups/resources?`$top=999"

do {
    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        if ($response -and $response.value) {
            $pimGroups += $response.value
        }
        $uri = $response.'@odata.nextLink'  # Handle pagination
    } catch {
        Write-Host "ERROR: Unable to retrieve PIM-managed groups. $_" -ForegroundColor Red
        exit 1
    }
} while ($uri -ne $null)

Write-Host "Total PIM-enabled groups found: $(($pimGroups | Measure-Object).Count)"
Write-Host "--------------------------------"

foreach ($group in $pimGroups) {
    Write-Host "$($group.displayName) | $($group.id)"
}

# --------------------------------
# Step 3: Fetch the User ID from Email
# --------------------------------
Write-Host "--------------------------------"
Write-Host "Checking eligible assignments for user: $UserEmail"
Write-Host "--------------------------------"

try {
    $user = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$UserEmail" -Headers $headers -Method Get
    $userId = $user.id  # Extract User ID from response
}
catch {
    Write-Host "ERROR: Unable to retrieve user details. $_" -ForegroundColor Red
    exit 1
}

$eligibleUserGroups = @()  # Store groups where the user is eligible

# --------------------------------
# Step 4: Loop through each PIM-managed group and check eligible assignments
# --------------------------------
foreach ($group in $pimGroups) {
    $groupId = $group.id

    $eligibleAssignments = @()
    $uri = "https://graph.microsoft.com/beta/privilegedAccess/aadGroups/roleAssignments?`$filter=resourceId eq '$groupId' and assignmentState eq 'Eligible'"

    do {
        try {
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
            if ($response -and $response.value) {
                $eligibleAssignments += $response.value
            }
            $uri = $response.'@odata.nextLink'
        } catch {
            Write-Host "ERROR: Unable to retrieve eligible assignments for group: $($group.displayName). $_" -ForegroundColor Red
            continue
        }
    } while ($uri -ne $null)

    # If the group has eligible assignments, print them
    if ($eligibleAssignments.Count -gt 0) {
        Write-Host "--------------------------------"
        Write-Host "Eligible Assignments for Group: $($group.displayName)"
        Write-Host "--------------------------------"
        Write-Host "Object Type    | User Principal Name                      | Display Name               | Actual Email"
        Write-Host "--------------|----------------------------------------|----------------------------|----------------------------"

        foreach ($assignment in $eligibleAssignments) {
            if (-not $assignment.subjectId) {
                Write-Host "Warning: Assignment missing subjectId. Skipping entry."
                continue
            }

            $subjectId = $assignment.subjectId
            $objectType = "Unknown"
            $userPrincipalName = "N/A"
            $displayName = "N/A"
            $actualEmail = "N/A"

            try {
                # Fetch user details based on subjectId
                $objectUri = "https://graph.microsoft.com/v1.0/directoryObjects/$subjectId"
                $objectDetails = Invoke-RestMethod -Uri $objectUri -Headers $headers -Method Get

                if ($objectDetails -and $objectDetails.'@odata.type') {
                    $objectType = $objectDetails.'@odata.type'

                    if ($objectType -eq "#microsoft.graph.user") {
                        $userPrincipalName = $objectDetails.userPrincipalName
                        $displayName = $objectDetails.displayName
                        $actualEmail = $objectDetails.mail

                        # If 'mail' is empty, try to find the correct email in 'proxyAddresses'
                        if (-not $actualEmail -and $objectDetails.proxyAddresses) {
                            $actualEmail = ($objectDetails.proxyAddresses | Where-Object { $_ -match "^SMTP:" } | Select-Object -First 1) -replace "^SMTP:", ""
                        }
                    }
                }
            } catch {
                Write-Host "Warning: Unable to fetch details for Subject ID: $subjectId. Error: $_"
            }

            Write-Host ("{0,-14} | {1,-40} | {2,-26} | {3}" -f $objectType, $userPrincipalName, $displayName, $actualEmail)

            # Check if the current user is in the eligible assignments
            if ($userId -eq $subjectId) {
                $eligibleUserGroups += @{
                    GroupName = $group.displayName
                    GroupId   = $group.id
                }
            }
        }
    }
}

# --------------------------------
# Step 5: Display final results - groups where user is eligible
# --------------------------------
Write-Host "--------------------------------"
Write-Host "Final List: Groups where $UserEmail is Eligible"
Write-Host "--------------------------------"

if ($eligibleUserGroups.Count -gt 0) {
    Write-Host "Group Name                                    | Group ID"
    Write-Host "---------------------------------------------|--------------------------------"

    foreach ($entry in $eligibleUserGroups) {
        Write-Host ("{0,-45} | {1}" -f $entry.GroupName, $entry.GroupId)
    }
} else {
    Write-Host "User is NOT eligible for any PIM-managed groups."
}
