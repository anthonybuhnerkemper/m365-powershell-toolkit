# M365 PowerShell Toolkit

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/ABK.M365Toolkit?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/ABK.M365Toolkit) [![Downloads](https://img.shields.io/powershellgallery/dt/ABK.M365Toolkit)](https://www.powershellgallery.com/packages/ABK.M365Toolkit)

PowerShell scripts for Microsoft 365 administration by Anthony Buhnerkemper.

A small, practical collection of read-only reporting scripts built on the Microsoft Graph PowerShell SDK and Exchange Online PowerShell. Each script uses least-privilege scopes, includes comment-based help, and exports results to CSV.


## Install from PowerShell Gallery

```powershell
Install-Module ABK.M365Toolkit -Scope CurrentUser
Import-Module ABK.M365Toolkit
Get-Command -Module ABK.M365Toolkit
```

Each script is also exported as a function with the same name and parameters (e.g. `Get-Help <FunctionName> -Full`). Prerequisite modules (Microsoft Graph, ExchangeOnlineManagement, ConfigMgr console, Citrix SDK, etc.) are not auto-installed; install the ones the functions you use need, as described below. The module source lives in [`ABK.M365Toolkit/`](ABK.M365Toolkit/).

## Scripts

| Script | Purpose |
| --- | --- |
| `Get-M365LicenseReport.ps1` | License SKU usage summary plus per-user license assignments, exported to CSV. |
| `Get-StaleEntraUsers.ps1` | Entra ID users with no sign-in in N days (uses `signInActivity`), exported to CSV. |
| `Get-MailboxForwardingAudit.ps1` | Exchange Online mailboxes forwarding externally via mailbox forwarding or inbox rules. |

## Requirements

- PowerShell 7.2+ (Windows PowerShell 5.1 also works for most scripts)
- [Microsoft.Graph](https://learn.microsoft.com/powershell/microsoftgraph/installation) module:
  `Install-Module Microsoft.Graph -Scope CurrentUser`
- For the forwarding audit: `Install-Module ExchangeOnlineManagement -Scope CurrentUser`
- `signInActivity` requires a Microsoft Entra ID P1/P2 license in the tenant.
- An account able to consent to the listed read-only scopes (e.g. Global Reader / Reports Reader).

## Usage

```powershell
Get-Help .\Get-StaleEntraUsers.ps1 -Full

.\Get-M365LicenseReport.ps1 -OutputPath .\reports
.\Get-StaleEntraUsers.ps1 -DaysInactive 90 -IncludeNeverSignedIn
.\Get-MailboxForwardingAudit.ps1 -InternalDomains contoso.com,contoso.onmicrosoft.com
```

All scripts are read-only: they report, they do not change anything.

## Disclaimer

Test in a non-production tenant first. Provided as-is, without warranty.

## License

Released under the [MIT License](LICENSE).
