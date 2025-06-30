# PowerShell Script to Find Computer Accounts Inactive for a User-Specified Number of Days
# Author: [Your Name]
# Date: [Today's Date]

# Define Parameters
$OU = "OU=Computers,OU=MyBusiness,DC=statewindowcorp,DC=local"

# Prompt user for number of inactive days
$DaysInactive = Read-Host "Enter the number of days of inactivity (e.g., 30, 60, 90)"

# Validate that input is a number
if (-not ($DaysInactive -as [int])) {
    Write-Host "Invalid input. Please enter a numeric value." -ForegroundColor Red
    exit
}

# Calculate the date threshold
$Time = (Get-Date).AddDays(-[int]$DaysInactive)

# Set Export Path dynamically based on input
$ExportPath = "C:\Reports\StaleComputers_${DaysInactive}Days.csv"

# Ensure the output directory exists
$directory = Split-Path $ExportPath
if (!(Test-Path -Path $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

# Search for stale computer accounts
Get-ADComputer -SearchBase $OU -Filter * -Properties LastLogonDate |
Where-Object { $_.LastLogonDate -lt $Time -or !$_.LastLogonDate } |
Select-Object Name, DistinguishedName, LastLogonDate |
Export-Csv -Path $ExportPath -NoTypeInformation

Write-Host "Stale computer report ($DaysInactive+ days inactive) successfully generated at: $ExportPath" -ForegroundColor Green
