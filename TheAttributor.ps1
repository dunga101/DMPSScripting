# Import the Active Directory module
Import-Module ActiveDirectory

# Specify the AD username; you can modify this to accept a parameter or prompt for input
$username = Read-Host "Enter the AD username"

# Retrieve the user object and include existing proxyAddresses if any
$user = Get-ADUser -Identity $username -Properties proxyAddresses
if (-not $user) {
    Write-Error "User '$username' was not found."
    exit
}

# Construct the new proxy addresses based on the username
$newProxies = @(
    "SMTP:$username@statecorp.com",
    "smtp:$username@statewindowcorp.onmicrosoft.com",
    "smtp:$username@statewindowcorp.mail.onmicrosoft.com"
)

# Retrieve the current proxyAddresses; initialize as an empty array if none exist
$currentProxies = @()
if ($user.proxyAddresses) {
    $currentProxies = $user.proxyAddresses
}

# Merge existing proxyAddresses with the new entries, ensuring no duplicates
$combinedProxies = $currentProxies.Clone()
foreach ($proxy in $newProxies) {
    if ($combinedProxies -notcontains $proxy) {
        $combinedProxies += $proxy
    }
}

# Define the remaining attributes
$targetAddress = "SMTP:$username@statewindowcorp.mail.onmicrosoft.com"
$extAttr1 = "ACE"
$extAttr2 = "AOE"

# Update the AD user with the new attributes
Set-ADUser -Identity $username -Replace @{
    proxyAddresses       = $combinedProxies;
    targetAddress        = $targetAddress;
    extensionAttribute1  = $extAttr1;
    extensionAttribute2  = $extAttr2
}

Write-Host "Attributes updated successfully for user '$username'."
