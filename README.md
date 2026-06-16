# Windows 11 Bloatware Removal

A PowerShell script for removing my personal most unnecessary apps from my personal PC. The script eliminates the apps for all existing users and deprovisions them so they do not automatically install for future users.

## What It Removes

The script targets these Windows 11 apps:

- Camera
- Feedback Hub
- Get Help
- Microsoft 365 Copilot
- Microsoft Bing
- Microsoft Clipchamp
- Microsoft Teams
- Microsoft To Do
- Mobile Devices
- News
- Outlook
- Phone Link
- Quick Assist
- Sticky Notes
- Weather

`Start Experiences App` is intentionally not removed because it is tied to Windows shell and Start menu functionality.

## Requirements

- Windows 11
- PowerShell
- Administrator privileges

## Usage

Open PowerShell as Administrator from the folder containing the script.

Preview what would be removed:

```powershell
.\bloatware-removal.ps1 -WhatIf
```

Run the removal:

```powershell
.\bloatware-removal.ps1
```

Run only installed app removal and skip provisioned package removal:

```powershell
.\bloatware-removal.ps1 -SkipProvisionedPackages
```

## What Installed and Provisioned Mean

Installed packages are apps registered for existing Windows user accounts. Removing these apps makes them disappear from current users.

Provisioned packages are default app templates in the Windows image. Removing these helps prevent the apps from automatically installing for new user profiles.

## Notes

- The script writes a timestamped log file beside the script after each run.
- Restart Windows after running the script so Start menu and Settings app lists refresh.
- Some Windows components are protected and should not be forcibly removed.
- Do not commit generated log files to GitHub because they may contain local usernames or system paths.

## Disclaimer

Use at your own risk. Review the script and run it with `-WhatIf` before applying changes.
