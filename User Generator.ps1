#-----------------------------------------------------------
# Unified AD Provisioning Script (with Set-ADUser -Clear fix)
# Tasks: User Creation → Attribute Updates → Group Copy → AD Sync
#-----------------------------------------------------------

# 0) IMPORT MODULES
Import-Module ActiveDirectory -ErrorAction Stop
Write-Host "✅ Loaded ActiveDirectory module."

# 1) DEFINE COMMON VARIABLES
$ouPath = "OU=SBSUsers,OU=Users,OU=MyBusiness,DC=statewindowcorp,DC=local"
Write-Host "`n🔍 Validating OU: $ouPath"
try {
    Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
} catch {
    Write-Error "❌ OU '$ouPath' not found. Exiting." 
    exit 1
}

#-----------------------------------------------------------
# TASK 1: CREATE NEW USER
#-----------------------------------------------------------
$firstName = Read-Host "Enter the user's FIRST name"
$lastName  = Read-Host "Enter the user's LAST name"
$fullName  = "$firstName $lastName"

Write-Host "Full name: $fullName"
if ((Read-Host "Press ENTER to confirm or type 'N' to cancel") -eq 'N') {
    Write-Host "Operation cancelled." 
    exit
}

# Generate unique SAMAccountName
$baseUserName = ($firstName.Substring(0,1) + $lastName).ToLower()
$userName     = $baseUserName
$i            = 2
while (Get-ADUser -Filter "samAccountName -eq '$userName'" -ErrorAction SilentlyContinue) {
    $userName = "$baseUserName$i"; $i++
}
Write-Host "Selected SAMAccountName: $userName"

# Check existence and create
if (Get-ADUser -Filter "samAccountName -eq '$userName'" -ErrorAction SilentlyContinue) {
    Write-Error "User '$userName' already exists. Exiting."
    exit
}

$upn      = "$userName@statecorp.com"
$password = Read-Host "Enter a temporary password" -AsSecureString

New-ADUser `
    -Name              $fullName `
    -GivenName         $firstName `
    -Surname           $lastName `
    -DisplayName       $fullName `
    -SamAccountName    $userName `
    -UserPrincipalName $upn `
    -Path              $ouPath `
    -AccountPassword   $password `
    -Enabled           $true `
    -PassThru | Out-Null

Set-ADUser -Identity $userName -PasswordNeverExpires $true
Write-Host "✅ Created user '$fullName' ($userName)."

#-----------------------------------------------------------
# TASK 2: UPDATE ATTRIBUTES
#-----------------------------------------------------------
if ((Read-Host "`nWould you like to update AD attributes for '$fullName'? (Y/N)") -eq 'Y') {
    $updateUser = $userName
} else {
    $updateUser = Read-Host "Enter an existing SAMAccountName to update"
}

$userObj      = Get-ADUser -Identity $updateUser -Properties proxyAddresses -ErrorAction Stop
$jobTitle     = Read-Host "Job Title"
$emailPrimary = "$updateUser@statecorp.com"

$extAttr1 = if ((Read-Host "Needs All Company Emp emails? (Y/N)") -eq 'Y') { 'ACE' } else { $null }
$extAttr2 = if ((Read-Host "Needs All Office Emp emails? (Y/N)")   -eq 'Y') { 'AOE' } else { $null }

# Normalize existing proxyAddresses to pure string[]
if ($userObj.proxyAddresses) {
    $currentProxies = @()
    foreach ($p in $userObj.proxyAddresses) {
        $currentProxies += [string]$p
    }
} else {
    $currentProxies = @()
}

# Define and normalize new proxy addresses
$newProxies = @(
    "SMTP:$updateUser@statecorp.com",
    "smtp:$updateUser@statewindowcorp.onmicrosoft.com",
    "smtp:$updateUser@statewindowcorp.mail.onmicrosoft.com"
) | ForEach-Object { [string]$_ }

# Merge uniquely into a pure string[]
$combinedProxies = @()
foreach ($proxy in $currentProxies + $newProxies) {
    if ($combinedProxies -notcontains $proxy) {
        $combinedProxies += $proxy
    }
}

# Prepare Replace hashtable
$replace = @{
    Title          = $jobTitle
    mail           = $emailPrimary
    targetAddress  = "SMTP:$updateUser@statewindowcorp.mail.onmicrosoft.com"
    proxyAddresses = $combinedProxies
}

# Use Set-ADUser -Clear to remove unwanted extensionAttributes
if ($extAttr1) {
    $replace['extensionAttribute1'] = $extAttr1
} else {
    Set-ADUser -Identity $updateUser -Clear extensionAttribute1
}

if ($extAttr2) {
    $replace['extensionAttribute2'] = $extAttr2
} else {
    Set-ADUser -Identity $updateUser -Clear extensionAttribute2
}

Set-ADUser -Identity $updateUser -Replace $replace
Write-Host "✅ Updated attributes for '$updateUser'."

#-----------------------------------------------------------
# TASK 3: COPY GROUP MEMBERSHIPS
#-----------------------------------------------------------
if ((Read-Host "`nCopy group memberships from another user? (Y/N)") -eq 'Y') {
    $source = Read-Host "Enter SOURCE user SAMAccountName"
    $target = $updateUser

    Write-Host "Fetching memberships of '$source'..."
    try {
        $sourceGroups = Get-ADPrincipalGroupMembership -Identity $source -ErrorAction Stop
    } catch {
        Write-Error "❌ Cannot fetch groups for '$source'. $_"
        exit 1
    }

    if (-not $sourceGroups) {
        Write-Warning "'$source' has no groups to copy."
    } else {
        Write-Host "Copying to '$target'..."
        foreach ($grp in $sourceGroups) {
            $isMember = Get-ADGroupMember -Identity $grp.DistinguishedName -Recursive |
                        Where-Object SamAccountName -EQ $target
            if ($isMember) {
                Write-Host " • Already in '$($grp.Name)'"
            } else {
                try {
                    Add-ADGroupMember -Identity $grp.DistinguishedName -Members $target -ErrorAction Stop
                    Write-Host " ✔ Added to '$($grp.Name)'"
                } catch {
                    Write-Warning " ⚠ Failed to add to '$($grp.Name)': $($_.Exception.Message)"
                }
            }
        }
        Write-Host "✅ Group copy complete."
    }
} else {
    Write-Host "Skipping group copy."
}

#-----------------------------------------------------------
# TASK 4: OPTIONAL AD SYNC
#-----------------------------------------------------------
if ((Read-Host "`nRun Azure AD Connect sync? (Y/N)") -eq 'Y') {
    if (Get-Module -ListAvailable ADSync) {
        Import-Module ADSync
        Start-ADSyncSyncCycle -PolicyType Delta
        Write-Host "✅ AD Sync initiated."
    } else {
        Write-Warning "⚠ ADSync module missing. Install Azure AD Connect to sync."
    }
} else {
    Write-Host "Skipping AD sync."
}

#-----------------------------------------------------------
# FINAL SUMMARY
#-----------------------------------------------------------
Write-Host "`n======================================="
Write-Host "Provisioning complete for user: $fullName"
Write-Host "SAMAccountName:    $userName"
Write-Host "Primary email:     $emailPrimary"
Write-Host "======================================="
