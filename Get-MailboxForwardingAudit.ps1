<#
.SYNOPSIS
    Audits Exchange Online mailboxes for forwarding to external recipients.

.DESCRIPTION
    Checks every user/shared mailbox for:
      1. Mailbox-level forwarding (ForwardingSmtpAddress / ForwardingAddress).
      2. Inbox rules that forward, redirect or forward-as-attachment to external addresses.
    An address is external when its domain is not in -InternalDomains (or, if not
    supplied, not an accepted domain of the tenant). Results are exported to CSV.

.PARAMETER InternalDomains
    Domains to treat as internal. If omitted, the tenant's accepted domains are used.

.PARAMETER OutputPath
    Full path of the CSV file. Defaults to .\MailboxForwardingAudit_<date>.csv

.PARAMETER SkipInboxRules
    Only check mailbox-level forwarding (much faster on large tenants).

.EXAMPLE
    .\Get-MailboxForwardingAudit.ps1

.EXAMPLE
    .\Get-MailboxForwardingAudit.ps1 -InternalDomains contoso.com -SkipInboxRules

.NOTES
    Author : Anthony Buhnerkemper
    Requires: ExchangeOnlineManagement (v3+)
    Role    : View-Only Recipients + View-Only Configuration (e.g. Global Reader)
    Inbox rule enumeration is slow; expect several seconds per mailbox.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$InternalDomains,

    [Parameter()]
    [string]$OutputPath = (Join-Path (Get-Location).Path ("MailboxForwardingAudit_{0}.csv" -f (Get-Date -Format 'yyyyMMdd'))),

    [Parameter()]
    [switch]$SkipInboxRules
)

#Requires -Modules ExchangeOnlineManagement

$ErrorActionPreference = 'Stop'

# Exchange Online uses RBAC roles rather than Graph scopes; a read-only role is sufficient.
Connect-ExchangeOnline -ShowBanner:$false

if (-not $InternalDomains) {
    $InternalDomains = (Get-AcceptedDomain).DomainName
}
$InternalDomains = $InternalDomains | ForEach-Object { $_.ToLower() }

function Test-IsExternal {
    <# Returns $true if the address' domain is not an internal domain. #>
    param([string]$Address)
    if ([string]::IsNullOrWhiteSpace($Address)) { return $false }
    # Rule recipients look like: "Name" [SMTP:user@domain.com]; strip to the address
    $clean = ($Address -replace '^.*\[(SMTP|smtp):', '' -replace '\]$', '' -replace '^smtp:', '').Trim()
    if ($clean -notmatch '@') { return $false }  # internal object (no SMTP domain)
    $domain = $clean.Split('@')[-1].ToLower()
    return ($InternalDomains -notcontains $domain)
}

$mailboxes = Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox, SharedMailbox `
    -Properties ForwardingSmtpAddress, ForwardingAddress, DeliverToMailboxAndForward

$results = [System.Collections.Generic.List[object]]::new()
$i = 0
foreach ($mbx in $mailboxes) {
    $i++
    Write-Progress -Activity 'Auditing mailboxes' -Status $mbx.UserPrincipalName -PercentComplete (($i / $mailboxes.Count) * 100)

    # 1. Mailbox-level SMTP forwarding
    if ($mbx.ForwardingSmtpAddress -and (Test-IsExternal $mbx.ForwardingSmtpAddress)) {
        $results.Add([pscustomobject]@{
            Mailbox      = $mbx.UserPrincipalName
            Type         = 'MailboxForwarding'
            RuleName     = ''
            Enabled      = $true
            ForwardTo    = $mbx.ForwardingSmtpAddress
            KeepCopy     = $mbx.DeliverToMailboxAndForward
        })
    }
    # ForwardingAddress points to a recipient object (often a mail contact)
    if ($mbx.ForwardingAddress) {
        $target = Get-Recipient -Identity $mbx.ForwardingAddress -ErrorAction SilentlyContinue
        if ($target -and (Test-IsExternal $target.PrimarySmtpAddress)) {
            $results.Add([pscustomobject]@{
                Mailbox   = $mbx.UserPrincipalName
                Type      = 'MailboxForwardingContact'
                RuleName  = ''
                Enabled   = $true
                ForwardTo = $target.PrimarySmtpAddress
                KeepCopy  = $mbx.DeliverToMailboxAndForward
            })
        }
    }

    # 2. Inbox rules
    if (-not $SkipInboxRules) {
        $rules = Get-InboxRule -Mailbox $mbx.UserPrincipalName -ErrorAction SilentlyContinue
        foreach ($rule in $rules) {
            $targets = @($rule.ForwardTo) + @($rule.ForwardAsAttachmentTo) + @($rule.RedirectTo) | Where-Object { $_ }
            $external = $targets | Where-Object { Test-IsExternal $_ }
            if ($external) {
                $results.Add([pscustomobject]@{
                    Mailbox   = $mbx.UserPrincipalName
                    Type      = 'InboxRule'
                    RuleName  = $rule.Name
                    Enabled   = $rule.Enabled
                    ForwardTo = ($external -join '; ')
                    KeepCopy  = -not $rule.DeleteMessage
                })
            }
        }
    }
}
Write-Progress -Activity 'Auditing mailboxes' -Completed

$results | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host "Checked $($mailboxes.Count) mailboxes; $($results.Count) external forwarding finding(s). Report: $OutputPath"

Disconnect-ExchangeOnline -Confirm:$false
