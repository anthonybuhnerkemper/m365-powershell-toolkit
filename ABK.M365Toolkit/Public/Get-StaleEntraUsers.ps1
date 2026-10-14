function Get-StaleEntraUsers {
    <#
    .SYNOPSIS
        Finds Entra ID users who have not signed in for a given number of days.

    .DESCRIPTION
        Uses the signInActivity property from Microsoft Graph to identify users whose
        last interactive and non-interactive sign-ins are both older than -DaysInactive.
        Results are exported to CSV. Requires Microsoft Entra ID P1 or P2.

    .PARAMETER DaysInactive
        Number of days without sign-in to treat as stale. Default 90.

    .PARAMETER IncludeNeverSignedIn
        Also include accounts with no recorded sign-in (created before the threshold).

    .PARAMETER IncludeGuests
        Include guest (B2B) accounts. By default only Member accounts are evaluated.

    .PARAMETER OutputPath
        Full path of the CSV file. Defaults to .\StaleEntraUsers_<date>.csv

    .EXAMPLE
        Get-StaleEntraUsers -DaysInactive 60 -IncludeNeverSignedIn

    .NOTES
        Author : Anthony Buhnerkemper
        Requires: Microsoft.Graph.Authentication, Microsoft.Graph.Users
        Scopes  : User.Read.All, AuditLog.Read.All
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(1, 3650)]
        [int]$DaysInactive = 90,

        [Parameter()]
        [switch]$IncludeNeverSignedIn,

        [Parameter()]
        [switch]$IncludeGuests,

        [Parameter()]
        [string]$OutputPath = (Join-Path (Get-Location).Path ("StaleEntraUsers_{0}.csv" -f (Get-Date -Format 'yyyyMMdd')))
    )


    $ErrorActionPreference = 'Stop'

    # signInActivity requires AuditLog.Read.All in addition to User.Read.All
    Connect-MgGraph -Scopes 'User.Read.All', 'AuditLog.Read.All' -NoWelcome

    $cutoff = (Get-Date).ToUniversalTime().AddDays(-$DaysInactive)
    $props  = 'id,displayName,userPrincipalName,userType,accountEnabled,createdDateTime,signInActivity'

    Write-Verbose "Retrieving users (cutoff: $cutoff UTC)..."
    $users = Get-MgUser -All -Property $props

    if (-not $IncludeGuests) {
        $users = $users | Where-Object { $_.UserType -eq 'Member' }
    }

    $results = foreach ($user in $users) {
        $interactive    = $user.SignInActivity.LastSignInDateTime
        $nonInteractive = $user.SignInActivity.LastNonInteractiveSignInDateTime

        # Most recent of the two sign-in timestamps (either may be null)
        $last = @($interactive, $nonInteractive) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1

        $isStale = $false
        if ($last) {
            $isStale = $last -lt $cutoff
        }
        elseif ($IncludeNeverSignedIn -and $user.CreatedDateTime -lt $cutoff) {
            $isStale = $true
        }

        if ($isStale) {
            [pscustomobject]@{
                DisplayName          = $user.DisplayName
                UserPrincipalName    = $user.UserPrincipalName
                UserType             = $user.UserType
                AccountEnabled       = $user.AccountEnabled
                CreatedDateTime      = $user.CreatedDateTime
                LastInteractive      = $interactive
                LastNonInteractive   = $nonInteractive
                DaysSinceLastSignIn  = if ($last) { [int]((Get-Date).ToUniversalTime() - $last).TotalDays } else { 'Never' }
            }
        }
    }

    $results | Sort-Object UserPrincipalName | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Host "Found $(@($results).Count) stale user(s). Report: $OutputPath"

    Disconnect-MgGraph | Out-Null
}

