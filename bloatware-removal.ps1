#Requires -RunAsAdministrator

<#
.SYNOPSIS
Removes selected Windows 11 apps for all users and deprovisions them for future users.

.EXAMPLE
.\bloatware-removal.ps1 -WhatIf

Preview the packages that would be removed.

.EXAMPLE
.\bloatware-removal.ps1

Remove the targeted apps.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$SkipProvisionedPackages
)

$ErrorActionPreference = 'Stop'

$targets = @(
    @{
        Label = 'Camera'
        StartAppNames = @('Camera')
        Patterns = @('Microsoft.WindowsCamera')
    },
    @{
        Label = 'Feedback Hub'
        StartAppNames = @('Feedback Hub')
        Patterns = @('Microsoft.WindowsFeedbackHub')
    },
    @{
        Label = 'Microsoft 365 Copilot'
        StartAppNames = @(
            'Microsoft 365 Copilot',
            'Microsoft 365'
        )
        Patterns = @(
            'Microsoft.MicrosoftOfficeHub',
            'Microsoft.Microsoft365Copilot',
            'Microsoft.Microsoft365Hub'
        )
    },
    @{
        Label = 'Microsoft Bing'
        StartAppNames = @(
            'Microsoft Bing',
            'Bing'
        )
        Patterns = @('Microsoft.BingSearch')
    },
    @{
        Label = 'Microsoft Clipchamp'
        StartAppNames = @(
            'Microsoft Clipchamp',
            'Clipchamp'
        )
        Patterns = @('Clipchamp.Clipchamp')
    },
    @{
        Label = 'Microsoft Teams'
        StartAppNames = @(
            'Microsoft Teams',
            'Teams'
        )
        Patterns = @(
            'MSTeams',
            'MicrosoftTeams',
            'Microsoft.Teams'
        )
    },
    @{
        Label = 'Microsoft To Do'
        StartAppNames = @(
            'Microsoft To Do',
            'To Do'
        )
        Patterns = @(
            'Microsoft.Todos',
            'Microsoft.ToDo'
        )
    },
    @{
        Label = 'News'
        StartAppNames = @('News')
        Patterns = @(
            'Microsoft.BingNews',
            'Microsoft.News'
        )
    },
    @{
        Label = 'Outlook'
        StartAppNames = @(
            'Outlook',
            'Outlook (new)'
        )
        Patterns = @('Microsoft.OutlookForWindows')
    },
    @{
        Label = 'Quick Assist'
        StartAppNames = @('Quick Assist')
        Patterns = @(
            'MicrosoftCorporationII.QuickAssist',
            'Microsoft.QuickAssist'
        )
    },
    @{
        Label = 'Sticky Notes'
        StartAppNames = @('Sticky Notes')
        Patterns = @('Microsoft.MicrosoftStickyNotes')
    },
    @{
        Label = 'Weather'
        StartAppNames = @('Weather')
        Patterns = @('Microsoft.BingWeather')
    },
    @{
        Label = 'Get Help'
        StartAppNames = @('Get Help')
        Patterns = @('Microsoft.GetHelp')
    },
    @{
        Label = 'Mobile Devices'
        StartAppNames = @('Mobile Devices')
        Patterns = @(
            'MicrosoftWindows.CrossDevice',
            'Microsoft.CrossDevice'
        )
    },
    @{
        Label = 'Phone Link'
        StartAppNames = @('Phone Link')
        Patterns = @('Microsoft.YourPhone')
    }
)

function Get-StartAppPackagePatterns {
    param(
        [Parameter(Mandatory)]
        [psobject[]]$StartApps,

        [Parameter(Mandatory)]
        [string[]]$Names
    )

    foreach ($startApp in $StartApps) {
        foreach ($name in $Names) {
            if ($startApp.Name -like $name) {
                $packageFamilyName = ([string]$startApp.AppID -split '!')[0]
                if (-not [string]::IsNullOrWhiteSpace($packageFamilyName)) {
                    $packageFamilyName
                    ($packageFamilyName -split '_')[0]
                }
            }
        }
    }
}

function Test-PackageMatch {
    param(
        [Parameter(Mandatory)]
        [psobject]$Package,

        [Parameter(Mandatory)]
        [string[]]$Patterns
    )

    $candidateValues = foreach ($propertyName in @('Name', 'PackageFullName', 'PackageFamilyName', 'DisplayName', 'PackageName')) {
        if ($Package.PSObject.Properties.Name -contains $propertyName) {
            $value = [string]$Package.$propertyName
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $value
            }
        }
    }

    foreach ($pattern in $Patterns) {
        foreach ($candidateValue in $candidateValues) {
            if ($candidateValue -eq $pattern -or $candidateValue -like "*$pattern*") {
                return $true
            }
        }
    }

    return $false
}

function Get-UniqueByProperty {
    param(
        [Parameter(ValueFromPipeline)]
        [psobject]$InputObject,

        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    begin {
        $seen = @{}
    }

    process {
        $key = [string]$InputObject.$PropertyName
        if (-not [string]::IsNullOrWhiteSpace($key) -and -not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $InputObject
        }
    }
}

function Add-Result {
    param(
        [System.Collections.Generic.List[psobject]]$Results,

        [Parameter(Mandatory)]
        [string]$App,

        [Parameter(Mandatory)]
        [string]$PackageType,

        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$Status
    )

    $Results.Add([pscustomobject]@{
        App = $App
        Type = $PackageType
        Package = $PackageName
        Status = $Status
    })
}

function Invoke-DismRemoveProvisionedPackage {
    param(
        [Parameter(Mandatory)]
        [string]$PackageName
    )

    $dismOutput = @(& dism.exe /Online /Remove-ProvisionedAppxPackage "/PackageName:$PackageName" 2>&1)
    $exitCode = $LASTEXITCODE
    $message = ($dismOutput | ForEach-Object { [string]$_ }) -join ' '

    [pscustomobject]@{
        Success = ($exitCode -eq 0)
        ExitCode = $exitCode
        Message = $message
    }
}

$removeAppxCommand = Get-Command Remove-AppxPackage -ErrorAction Stop
$removeAppxSupportsAllUsers = $removeAppxCommand.Parameters.ContainsKey('AllUsers')
$results = [System.Collections.Generic.List[psobject]]::new()

Write-Host 'Reading installed Appx packages...' -ForegroundColor Cyan
$installedPackages = @(Get-AppxPackage -AllUsers)

try {
    Write-Host 'Reading Start menu app registrations...' -ForegroundColor Cyan
    $startApps = @(Get-StartApps)
}
catch {
    Write-Warning "Could not read Start menu app registrations: $($_.Exception.Message)"
    $startApps = @()
}

if (-not $SkipProvisionedPackages) {
    Write-Host 'Reading provisioned Appx packages...' -ForegroundColor Cyan
    $provisionedPackages = @(Get-AppxProvisionedPackage -Online)
}
else {
    $provisionedPackages = @()
}

foreach ($target in $targets) {
    if ($target.ContainsKey('StartAppNames') -and $startApps.Count -gt 0) {
        $discoveredPatterns = @(
            Get-StartAppPackagePatterns -StartApps $startApps -Names $target.StartAppNames
        )

        if ($discoveredPatterns.Count -gt 0) {
            $target.Patterns = @($target.Patterns + $discoveredPatterns | Sort-Object -Unique)
        }
    }

    if (-not $SkipProvisionedPackages) {
        $provisionedMatches = @(
            $provisionedPackages |
                Where-Object { Test-PackageMatch -Package $_ -Patterns $target.Patterns } |
                Get-UniqueByProperty -PropertyName PackageName
        )

        if ($provisionedMatches.Count -eq 0) {
            Add-Result -Results $results -App $target.Label -PackageType 'Provisioned' -PackageName '(not found)' -Status 'Skipped'
        }

        foreach ($package in $provisionedMatches) {
            $packageName = $package.PackageName
            $action = "Remove provisioned Appx package for $($target.Label)"

            if ($PSCmdlet.ShouldProcess($packageName, $action)) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $packageName -ErrorAction Stop | Out-Null
                    Add-Result -Results $results -App $target.Label -PackageType 'Provisioned' -PackageName $packageName -Status 'Removed'
                }
                catch {
                    $firstError = $_.Exception.Message
                    $dismResult = Invoke-DismRemoveProvisionedPackage -PackageName $packageName

                    if ($dismResult.Success) {
                        Add-Result -Results $results -App $target.Label -PackageType 'Provisioned' -PackageName $packageName -Status "Removed with DISM after PowerShell failed: $firstError"
                    }
                    else {
                        Add-Result -Results $results -App $target.Label -PackageType 'Provisioned' -PackageName $packageName -Status "Failed. PowerShell: $firstError DISM exit code $($dismResult.ExitCode): $($dismResult.Message)"
                    }
                }
            }
            else {
                Add-Result -Results $results -App $target.Label -PackageType 'Provisioned' -PackageName $packageName -Status 'Preview'
            }
        }
    }

    $installedMatches = @(
        $installedPackages |
            Where-Object { Test-PackageMatch -Package $_ -Patterns $target.Patterns } |
            Get-UniqueByProperty -PropertyName PackageFullName
    )

    if ($installedMatches.Count -eq 0) {
        Add-Result -Results $results -App $target.Label -PackageType 'Installed' -PackageName '(not found)' -Status 'Skipped'
    }

    foreach ($package in $installedMatches) {
        $packageName = $package.PackageFullName
        $action = "Remove installed Appx package for $($target.Label)"

        if ($PSCmdlet.ShouldProcess($packageName, $action)) {
            try {
                if ($removeAppxSupportsAllUsers) {
                    Remove-AppxPackage -Package $packageName -AllUsers -ErrorAction Stop
                }
                else {
                    Remove-AppxPackage -Package $packageName -ErrorAction Stop
                }

                Add-Result -Results $results -App $target.Label -PackageType 'Installed' -PackageName $packageName -Status 'Removed'
            }
            catch {
                Add-Result -Results $results -App $target.Label -PackageType 'Installed' -PackageName $packageName -Status "Failed: $($_.Exception.Message)"
            }
        }
        else {
            Add-Result -Results $results -App $target.Label -PackageType 'Installed' -PackageName $packageName -Status 'Preview'
        }
    }
}

Write-Host ''
Write-Host 'Removal summary:' -ForegroundColor Cyan
$sortedResults = $results | Sort-Object App, Type, Package
$sortedResults | Format-Table -AutoSize -Wrap | Out-String -Width 4096 | Write-Host

$logPath = Join-Path -Path $PSScriptRoot -ChildPath ('Remove-Windows11-Bloat-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
$sortedResults | Format-List | Out-String -Width 4096 | Set-Content -LiteralPath $logPath -Encoding UTF8

Write-Host ''
Write-Host "Detailed log: $logPath" -ForegroundColor Cyan
Write-Host 'Done. Restart Windows to let Start menu and Settings refresh their app lists.' -ForegroundColor Green
