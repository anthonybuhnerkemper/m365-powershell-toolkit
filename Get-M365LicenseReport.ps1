<#
.SYNOPSIS
    Reports Microsoft 365 license SKU usage and per-user license assignments.

.DESCRIPTION
    Connects to Microsoft Graph with read-only scopes and produces two CSV files:
      - LicenseSkuSummary_<date>.csv : each subscribed SKU with enabled, consumed and available units.
      - UserLicenseAssignments_<date>.csv : one row per user per assigned SKU.

.PARAMETER OutputPath
    Folder for the CSV files. Created if it does not exist. Defaults to the current folder.

.PARAMETER SkipDisconnect
    Leave the Graph session connected when the script finishes.

.EXAMPLE
    .\Get-M365LicenseReport.ps1 -OutputPath .\reports

.NOTES
    Author : Anthony Buhnerkemper
    Requires: Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement
    Scopes  : Organization.Read.All, User.Read.All
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = (Get-Location).Path,

    [Parameter()]
    [switch]$SkipDisconnect
)

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement

$ErrorActionPreference = 'Stop'

# Least-privilege, read-only scopes
Connect-MgGraph -Scopes 'Organization.Read.All', 'User.Read.All' -NoWelcome

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory | Out-Null
}
$stamp = Get-Date -Format 'yyyyMMdd'

# --- SKU summary -----------------------------------------------------------
Write-Verbose 'Retrieving subscribed SKUs...'
$skus = Get-MgSubscribedSku -All

# Lookup table SkuId -> SkuPartNumber for the per-user section
$skuLookup = @{}
foreach ($sku in $skus) { $skuLookup[$sku.SkuId.ToString()] = $sku.SkuPartNumber }

$skuSummary = foreach ($sku in $skus) {
    [pscustomobject]@{
        SkuPartNumber = $sku.SkuPartNumber
        SkuId         = $sku.SkuId
        Enabled       = $sku.PrepaidUnits.Enabled
        Suspended     = $sku.PrepaidUnits.Suspended
        Warning       = $sku.PrepaidUnits.Warning
        Consumed      = $sku.ConsumedUnits
        Available     = $sku.PrepaidUnits.Enabled - $sku.ConsumedUnits
    }
}
$skuFile = Join-Path $OutputPath "LicenseSkuSummary_$stamp.csv"
$skuSummary | Sort-Object SkuPartNumber | Export-Csv -Path $skuFile -NoTypeInformation

# --- Per-user assignments --------------------------------------------------
Write-Verbose 'Retrieving users and license assignments...'
$users = Get-MgUser -All -Property 'id,displayName,userPrincipalName,accountEnabled,department,assignedLicenses' |
    Where-Object { $_.AssignedLicenses.Count -gt 0 }

$assignments = foreach ($user in $users) {
    foreach ($lic in $user.AssignedLicenses) {
        $id = $lic.SkuId.ToString()
        [pscustomobject]@{
            DisplayName       = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            AccountEnabled    = $user.AccountEnabled
            Department        = $user.Department
            SkuPartNumber     = if ($skuLookup.ContainsKey($id)) { $skuLookup[$id] } else { $id }
            DisabledPlans     = $lic.DisabledPlans.Count
        }
    }
}
$userFile = Join-Path $OutputPath "UserLicenseAssignments_$stamp.csv"
$assignments | Sort-Object UserPrincipalName | Export-Csv -Path $userFile -NoTypeInformation

Write-Host "SKU summary : $skuFile ($($skuSummary.Count) SKUs)"
Write-Host "Assignments : $userFile ($($assignments.Count) rows)"

if (-not $SkipDisconnect) { Disconnect-MgGraph | Out-Null }
