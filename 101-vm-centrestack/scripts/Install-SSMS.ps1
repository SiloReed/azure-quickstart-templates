<#
.Synopsis
    Installs SQL Server Managment Studio
.DESCRIPTION
    Installs SQL Server Managment Studio
.EXAMPLE
    .\Install-SSMS.ps1
.NOTES 
    Author: Jeff Reed
    Name: Install-MySQL.ps1
    Created: 2018-12-03
    
    Version History
    2018-12-03  1.0.0   Initial version
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
Param(
    [switch] $SkipServer = $false
)

#region functions
#endregion functions

#region Script Body
# Start a stopwatch to time the entire script execution
$swScript = [System.Diagnostics.Stopwatch]::StartNew()

# Enable verbose output
$VerbosePreference = "Continue"

# Get this script
$ThisScript = $Script:MyInvocation.MyCommand
# Get the directory of this script
$scriptDir = Split-Path $ThisScript.Path -Parent
# Get the script file
$scriptFile = Get-Item $ThisScript.Path
# Get the name of this script
$scriptName = $scriptFile.Name
# Get the name of the script less the extension
$scriptBaseName = $scriptFile.BaseName

# Define folder where log files are written
$logDir = Join-Path $scriptDir "Logs"
if ((Test-Path $logDir) -eq $FALSE) {
    New-Item $logDir -type directory | Out-Null
}

# The new logfile will be created every day
$logdate = Get-Date -f "yyyy-MM-dd_HH-mm-ss"
$script:log = Join-Path $logDir ($scriptBaseName + "_" + $logdate + ".log")
Write-Output ("Log file: {0}" -f $script:log)

. (Join-Path $scriptDir "Common-Functions.ps1")

# Force TLSv1.2 else Invoke-WebRequest may throw "The underlying connection was closed: An unexpected error occurred on a send."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Specify the location where downloads will be saved
$downloadsFolder = Join-Path $env:UserProfile "Downloads"
if (-not (Test-Path $downloadsFolder)) {
    # Create the folder as necessary
    New-Item -Path $downloadsFolder -ItemType Directory | Out-Null
}

# Download SQL Server Managment Studio installer package
$uriSSMS = 'https://download.microsoft.com/download/D/D/4/DD495084-ADA7-4827-ADD3-FC566EC05B90/SSMS-Setup-ENU.exe'
$fileName = $uriSSMS.Split('/') | Select-Object -Last 1
$installerPath = Join-Path $downloadsFolder $fileName
Out-Log -Level Verbose -Message ("Downloading {0} ..." -f $uriSSMS)
$progressPreference = 'silentlyContinue'
try {
    $m = Measure-Command { Invoke-WebRequest -Uri $uriSSMS -OutFile $installerPath }
}
catch {
    $FailedItem = $_.Exception.ItemName 
    $ErrorMessage = $_.Exception.Message
    Out-Log -Level Error -Message ("An error occurred while downloading {0} to {1}. Failed item: {2}. Exception Message: {3}" -f $uriSSMS, $installerPath, $FailedItem, $ErrorMessage)
    Throw $ErrorMessage
}
$progressPreference = 'Continue'
Out-Log -Level Verbose -Message ("Completed download in: {0:g}" -f $m)
$argList = @('/install', '/quiet', '/passive', '/norestart')
try {
    $m = Measure-Command { Start-Process -FilePath $installerPath -ArgumentList $argList -Wait -Verbose }
}
catch {
    $FailedItem = $_.Exception.ItemName
    $ErrorMessage = $_.Exception.Message
    Out-Log -Level Error -Message ("An error occurred while executing {0}. Failed item: {1}. Exception Message: {2}" -f $installerPath, $FailedItem, $ErrorMessage)
    Throw $ErrorMessage
}
Out-Log -Level Verbose -Message ("SQL Server Management Studio installation completed in: {0:g}" -f $m)

#endregion Script Body