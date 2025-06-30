<#
.SYNOPSIS
  Copy all security **and** distribution group memberships from one AD user to another within a specific OU,
  prompting interactively for source and target usernames.

.DESCRIPTION
  1. Load the ActiveDirectory module.
  2. Verify the OU distinguishedName (OUDN) exists.
  3. Prompt for source and target sAMAccountNames.
  4. Retrieve **all** group memberships (security + distribution) for the source user.
  5. Confirm the target user exists in that same OU.
  6. Add the target user to each group the source user belongs to (skipping already-member groups).
#>

# 1) Import AD module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "❌ Cannot load the ActiveDirectory module. Ensure RSAT is installed and run this session as Administrator."
    exit 1
}

# 2) Define and verify OU DN
$ouPath = "OU=SBSUsers,OU=Users,OU=MyBusiness,DC=statewindowcorp,DC=local"
Write-Host "Validating OU: $ouPath"
try {
    Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
}
catch {
    Write-Error "❌ The specified OU DN '$ouPath' is not valid or could not be found."
    exit 1
}

# 3) Prompt for source and target
$sourceUserName = Read-Host "Enter the SOURCE user sAMAccountName"
$targetUserName = Read-Host "Enter the TARGET user sAMAccountName"

if ([string]::IsNullOrWhiteSpace($sourceUserName) -or [string]::IsNullOrWhiteSpace($targetUserName)) {
    Write-Error "❌ Both source and target usernames must be provided."
    exit 1
}

# 4) Fetch all group memberships for the source user
Write-Host "Fetching all group memberships for '$sourceUserName'..."
try {
    $sourceGroups = Get-ADPrincipalGroupMembership -Identity $sourceUserName -ErrorAction Stop
}
catch {
    Write-Error "❌ Failed to retrieve groups for '$sourceUserName'. $_"
    exit 1
}

if (-not $sourceGroups) {
    Write-Warning "'$sourceUserName' has no group memberships to copy."
    exit 0
}

# 5) Verify target user exists in the OU
Write-Host "Verifying existence of '$targetUserName' in OU..."
try {
    $null = Get-ADUser `
        -Filter "SamAccountName -eq '$targetUserName'" `
        -SearchBase $ouPath `
        -ErrorAction Stop
}
catch {
    Write-Error "❌ Target user '$targetUserName' not found in OU '$ouPath'."
    exit 1
}

# 6) Copy memberships (idempotent)
Write-Host "Copying group memberships from '$sourceUserName' to '$targetUserName'..."
foreach ($group in $sourceGroups) {
    $already = Get-ADGroupMember -Identity $group.DistinguishedName -Recursive |
               Where-Object { $_.SamAccountName -eq $targetUserName }
    if ($already) {
        Write-Host "   • Already in '$($group.Name)' ($($group.GroupCategory) group)"
        continue
    }

    try {
        Add-ADGroupMember -Identity $group.DistinguishedName -Members $targetUserName -ErrorAction Stop
        Write-Host "   ✔ Added '$targetUserName' to '$($group.Name)' ($($group.GroupCategory) group)"
    }
    catch {
        Write-Warning "   ⚠ Failed to add to '$($group.Name)': $($_.Exception.Message)"
    }
}

Write-Host "`n✅ Operation complete!"
