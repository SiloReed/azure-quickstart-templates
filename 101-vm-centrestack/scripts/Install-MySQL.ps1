<#
.Synopsis
    Installs MySQL Community Edition
.DESCRIPTION
    Installs the following MySQL Community Edition products:
    * Server
    * Workbench
    * Connector/NET
.EXAMPLE
    .\Install-MySQL.ps1
.NOTES 
    Author: Jeff Reed
    Name: Install-MySQL.ps1
    Created: 2018-10-23
    
    Version History
    2018-09-24  1.0.0   Initial version
    2018-09-24  1.0.1   Minor tweaks
    2018-09-24  1.0.2   Create csmain database and csuser user for principle of least privilege
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
Param(
    [switch] $SkipServer = $false
)

#region functions
function Install-Product {
    <#
    .SYNOPSIS
        Calls MySQLInstallerConsole.exe to install MySQL products
    .DESCRIPTION
        Calls MySQLInstallerConsole.exe to install MySQL products
    .EXAMPLE
        Install-Product -Product Server
    .EXAMPLE
        Install-Product -Product Workbench
    .EXAMPLE
        Install-Product -Product 'Connector/NET'
    .PARAMETER Product 
        The product to install
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true, ValueFromPipeline = $false)]
        [ValidateSet('Server', 'Workbench', 'Connector/NET')]
        [string] $Product
    )
    
    switch ($Product) {
        'Server' { 
            $version = '5.7.24'
            $prodPlatform = $platform
            $fileBaseName = "MySQLInstaller_Server"
            
        }
        'Workbench' {
            $version = '8.0.13'
            $prodPlatform = $platform
            $fileBaseName = "MySQLInstaller_Workbench"
        }
        'Connector/NET' {
            $version = '8.0.13'
            # Connect/NET is x86 only
            $prodPlatform = 'x86'
            $fileBaseName = "MySQLInstaller_ConnectorNet"
        }
    }
    # Write install logs to temp
    $fileErrLog = Join-Path $env:TEMP ("{0}_StdErr.log" -f $fileBaseName)
    $fileOutputLog = Join-Path $env:TEMP ("{0}_StdOut.log" -f $fileBaseName)
    $productString = ("{0};{1};{2}" -f $Product, $version, $prodPlatform)

    $argList = @('community', 'install', $productString, '-silent')

    if ($platform -eq "x64") {
        # 64 bit
        $exePath = "C:\Program Files (x86)\MySQL\MySQL Installer for Windows\MySQLInstallerConsole.exe"
    } else {
        # 32 bit
        $exePath = "C:\Program Files\MySQL\MySQL Installer for Windows\MySQLInstallerConsole.exe"
    }
    
    $m = Measure-Command {
        try {
            $proc = Start-Process -FilePath $exePath -ArgumentList $argList -Wait -RedirectStandardError $fileErrLog -RedirectStandardOutput $fileOutputLog -PassThru -Verbose 
        }
        catch {
            $FailedItem = $_.Exception.ItemName
            $ErrorMessage = $_.Exception.Message
            Out-Log -Level Error -Message ("An error occurred while executing {0}. Failed item: {1}. Exception Message: {2}" -f $exePath, $FailedItem, $ErrorMessage)
            Throw $ErrorMessage
        }
    }
    Out-Log -Level Verbose -Message ("MySQLInstaller completed in: {0:g}" -f $m)
    
    Out-Log -Level Verbose -Message ("MySQLInstaller exit code: {0}" -f $proc.ExitCode)
    if ($proc.ExitCode -ne 0) {
        Get-Content $fileErrLog
        Throw $proc.ExitCode
    } else {
        Get-Content $fileOutputLog
    }
    
    # Remove zero byte files
    $outputFiles = @($fileOutputLog, $fileErrLog)
    $outputFiles | ForEach-Object {
        if ((Get-Item $_).Length -eq 0) {
            # Remove the file if it's zero length
            Remove-Item $_
        }
    }
} # end function Install-Product

function Install-VCRuntime {
    <#
    .SYNOPSIS
        Downloads and installs the Visual C++ runtime specified by the caller
    .DESCRIPTION
        Downloads and installs the Visual C++ runtime specified by the caller
    .EXAMPLE
        Install-VCRuntime -URI 'http://download.microsoft.com/download/C/C/2/CC2DF5F8-4454-44B4-802D-5EA68D086676/vcredist_x64.exe' -Name 'Microsoft Visual C++ 2013 Update 5 Redistributable x64'
    .PARAMETER URI 
        The URI of the product to download and install
    .PARAMETER Name
        The display name that will be output
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true, ValueFromPipeline = $false)]
        [string] $URI,

        [Parameter(Mandatory=$true, ValueFromPipeline = $false)]
        [string] $Name

    )
    $fileName = $URI.Split('/') | Select-Object -Last 1
    $outputFile = Join-Path $downloadsFolder $fileName

    # Download and install 
    Out-Log -Level Verbose -Message ("Downloading {0} ..." -f $URI)
    $progressPreference = 'silentlyContinue'
    $m = Measure-Command {
        try {
            Invoke-WebRequest -Uri $URI -OutFile $outputFile
        }
        catch {
            $FailedItem = $_.Exception.ItemName
            $ErrorMessage = $_.Exception.Message
            Out-Log -Level Error -Message ("An error occurred while downloading {0}. Failed item: {1}. Exception Message: {2}" -f $URI, $FailedItem, $ErrorMessage)
            Throw $ErrorMessage
        }
    }
    $progressPreference = 'Continue'
    Out-Log -Level Verbose -Message ("Completed download in: {0:g}" -f $m)

    $fileErrLog = Join-Path $env:TEMP ("{0}_StdErr.log" -f $fileBaseName)
    $fileOutputLog = Join-Path $env:TEMP ("{0}_StdOut.log" -f $fileBaseName)
    $argList = @('/install', '/passive', '/norestart')
    $m = Measure-Command {
        try {
            Start-Process -FilePath $outputFile -ArgumentList $argList -Wait -Verbose
        }
        catch {
            $FailedItem = $_.Exception.ItemName
            $ErrorMessage = $_.Exception.Message
            Out-Log -Level Error -Message ("An error occurred while executing {0}. Failed item: {1}. Exception Message: {2}" -f $outputFile, $FailedItem, $ErrorMessage)
            Throw $ErrorMessage
        }
    }

    Out-Log -Level Verbose -Message ("'{0}' installation completed in: {1:g}." -f $outputFile, $m)

} # end function Install-VCRuntime

function Start-Command {
    <#
    .SYNOPSIS
        Executes a MySQL command to configure the system
    .DESCRIPTION
        Executes a MySQL command to configure the system
    .EXAMPLE
        Start-Command -Path -ArgList -Action
    .PARAMETER Path 
        The path to the executable
    .PARAMETER ArgList
        An array of command line arguments
    .PARAMETER Action
        The name of the action (used for output log file names)
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true, ValueFromPipeline = $false)]
        [string] $Path,

        [Parameter(Mandatory=$true, ValueFromPipeline = $false)]
        [string[]] $ArgList,

        [Parameter(Mandatory=$true, ValueFromPipeline = $false)]
        [string] $Action
    )

    $fileErrLog = Join-Path $env:TEMP ("{0}_StdErr.log" -f $Action)
    $fileOutputLog = Join-Path $env:TEMP ("{0}_StdOut.log" -f $Action)
    
    Out-Log -Level Verbose -Message ("Executing: {0} {1}" -f $Path, [string] $ArgList)
    $m = Measure-Command {
        try {
            $proc = Start-Process -FilePath $Path -ArgumentList $ArgList -Wait -RedirectStandardError $fileErrLog -RedirectStandardOutput $fileOutputLog -PassThru -Verbose
        }
        catch {
            $FailedItem = $_.Exception.ItemName
            $ErrorMessage = $_.Exception.Message
            Out-Log -Level Error -Message ("An error occurred while executing {0}. Failed item: {1}. Exception Message: {2}" -f $Path, $FailedItem, $ErrorMessage)
            Throw $ErrorMessage
        }
 
    }
    Out-Log -Level Verbose -Message ("mysqld install exit code: {0}" -f $proc.ExitCode)
    if ($proc.ExitCode -ne 0) {
        Get-Content $fileErrLog
    } else {
        Get-Content $fileOutputLog
    }
    # Remove zero byte files
    $outputFiles = @($fileOutputLog, $fileErrLog)
    $outputFiles | ForEach-Object {
        if ((Get-Item $_).Length -eq 0) {
            # Remove the file if it's zero length
            Remove-Item $_
        }
    }
} #end function Start-Command

#endregion functions
#region Here-String
# Set up a Here-String of the text that will be saved in my-template.ini
$iniText = @"
# MySQL Server Instance Configuration File
# ----------------------------------------------------------------------
# For advice on how to change settings please see
# http://dev.mysql.com/doc/refman/5.7/en/server-configuration-defaults.html

[client]
port=3306

[mysql]
no-beep

[mysqld]
port=3306
basedir="C:/Program Files/MySQL/MySQL Server 5.7/"
datadir=C:/ProgramData/MySQL/MySQL Server 5.7/data
default-storage-engine=INNODB
sql-mode="STRICT_TRANS_TABLES,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION"
log-output=FILE
general-log=0
general_log_file="%COMPUTERNAME%.log"
slow-query-log=1
slow_query_log_file="%COMPUTERNAME%-slow.log"
long_query_time=10
log-error="%COMPUTERNAME%.err"
server-id=1
lower_case_table_names=1
secure-file-priv="C:/ProgramData/MySQL/MySQL Server 5.7/Uploads"
max_connections=151
table_open_cache=2000
tmp_table_size=16M
thread_cache_size=10
myisam_max_sort_file_size=100G
myisam_sort_buffer_size=8M
key_buffer_size=8M
read_buffer_size=0
read_rnd_buffer_size=0
innodb_flush_log_at_trx_commit=1
innodb_log_buffer_size=1M
innodb_buffer_pool_size=8M
innodb_log_file_size=48M
innodb_thread_concurrency=8
innodb_autoextend_increment=64
innodb_buffer_pool_instances=8
innodb_concurrency_tickets=5000
innodb_old_blocks_time=1000
innodb_open_files=300
innodb_stats_on_metadata=0
innodb_file_per_table=1
innodb_checksum_algorithm=0
back_log=80
flush_time=0
join_buffer_size=256K
max_allowed_packet=4M
max_connect_errors=100
open_files_limit=4161
sort_buffer_size=256K
table_definition_cache=1400
binlog_row_event_max_size=8K
sync_master_info=10000
sync_relay_log=10000
sync_relay_log_info=10000
"@
#endregion Here-String
#region Script Body
#region Setup
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

# Check if TCP port 3306 is already in use, if it is throw an error
$tcpPort = 3306
$tcpConn = Get-NetTCPConnection | 
    Where-Object {$_.LocalPort -eq $tcpPort -and ($_.LocalAddress -eq '127.0.0.1' -or $_.LocalAddress -eq '0.0.0.0')} | 
    Select-Object -First 1
if ($null -ne $tcpConn) {
    $tcpProcess = Get-Process -Id $tcpConn.OwningProcess
    Out-Log -Level Error -Message ("Unable to continue. TCP port {0} is already owned by the process named {1} `n({2})" -f $tcpPort, $tcpProcess.Name, $tcpProcess.Path )
}

# Force TLSv1.2 else Invoke-WebRequest may throw "The underlying connection was closed: An unexpected error occurred on a send."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Get the user's Documents folder for output files
$myDocs = Join-Path $env:UserProfile "Documents"
Out-Log -Level Info -Message ("Documents directory is '{0}'" -f $myDocs)
Out-Log -Level Info -Message ("Temp directory is '{0}'" -f $env:TEMP)

# This will return '32-bit' or '64-bit'
$osArchitecture = (Get-WmiObject -Class Win32_OperatingSystem).OSArchitecture

if ($osArchitecture -eq '64-bit') {
    # Make sure 64-bit PowerShell is running on 64-bit Windows
    if ([System.IntPtr]::Size -eq 8) {
        $platform = "x64"
    }
    else {
        $m = "This script is not supported in a 32-bit PowerShell session on 64-bit Windows. Please execute this script within a 64-bit PowerShell session."
        Out-Log -Level Error -Message $m
        Throw $m
    }
} 
else {
    $platform = "x86"
}

# Specify the location where downloads will be saved
$downloadsFolder = Join-Path $env:UserProfile "Downloads"
if (-not (Test-Path $downloadsFolder)) {
    # Create the folder as necessary
    New-Item -Path $downloadsFolder -ItemType Directory | Out-Null
}
#endregion Setup

#region MySQL Server install

# Download and install Microsoft Visual C++ 2013 Update 5 Redistributable
if ($platform -eq "x64") {
    # 64 bit
    $htParams = @{
        URI = 'http://download.microsoft.com/download/0/5/6/056DCDA9-D667-4E27-8001-8A0C6971D6B1/vcredist_x64.exe'
        Name = 'Microsoft Visual C++ 2013 Update 5 Redistributable x64'
    }
} else {
    # 32 bit
    $htParams = @{
        URI = 'http://download.microsoft.com/download/0/5/6/056DCDA9-D667-4E27-8001-8A0C6971D6B1/vcredist_x86.exe'
        Name = 'Microsoft Visual C++ 2013 Update 5 Redistributable x86'
    }
}
Install-VCRuntime @htParams

# Download MySQL installer package
$uriMySQL = 'https://cdn.mysql.com//Downloads/MySQLInstaller/mysql-installer-web-community-5.7.24.0.msi'

$fileName = $uriMySQL.Split('/') | Select-Object -Last 1
$outputFile = Join-Path $downloadsFolder $fileName
Out-Log -Level Verbose -Message ("Downloading {0} ..." -f $uriMySQL)
$progressPreference = 'silentlyContinue'
$m = Measure-Command {
    try {
        Invoke-WebRequest -Uri $uriMySQL -OutFile $outputFile
    }
    catch {
        $FailedItem = $_.Exception.ItemName 
        $ErrorMessage = $_.Exception.Message
        Out-Log -Level Error -Message ("An error occurred while downloading {0} to {1}. Failed item: {2}. Exception Message: {3}" -f $uriMySQL, $outputFile, $FailedItem, $ErrorMessage)
        Throw $ErrorMessage
    }
}

$progressPreference = 'Continue'
Out-Log -Level Verbose -Message ("Completed download in: {0:g}" -f $m)
$argList = @('/i', $outputFile, '/passive')
$m = Measure-Command {
    try {
        Start-Process -FilePath msiexec.exe -ArgumentList $argList -Wait -Verbose
    }
    catch {
        $FailedItem = $_.Exception.ItemName
        $ErrorMessage = $_.Exception.Message
        Out-Log -Level Error -Message ("An error occurred while executing msiexec.exe. Failed item: {0}. Exception Message: {1}" -f $FailedItem, $ErrorMessage)
        Throw $ErrorMessage
    }
}

Out-Log -Level Verbose -Message ("MySQLInstaller installation completed in: {0:g}" -f $m)

if ($PSBoundParameters.ContainsKey('SkipServer')) {
    Out-Log -Level Info -Message "SkipServer argument specified so MySQL Server will not be installed."
}
else {
    Install-Product -Product "Server"

    # Create default Data directory
    $dataDir = 'C:/ProgramData/MySQL/MySQL Server 5.7/data'
    if (-not (Test-Path $dataDir) ) {
        New-Item -Path $dataDir -ItemType Directory | Out-Null
    }
    
    # Create Uploads directory
    $uploadsDir = 'C:/ProgramData/MySQL/MySQL Server 5.7/Uploads'
    if (-not (Test-Path $uploadsDir) ) {
        New-Item -Path $uploadsDir -ItemType Directory | Out-Null
    }
    
    # Replace %COMPUTERNAME% string in Here-String with actual computername
    $iniText = $iniText.Replace('%COMPUTERNAME%', $env:ComputerName)
    # Write a my.ini file from the Here-String text
    $defaultsFile = 'C:/ProgramData/MySQL/MySQL Server 5.7/my.ini'
    [System.IO.File]::WriteAllText($defaultsFile, $iniText )
    
    # Generate an 8 character random password and save it in the mysql-init.txt file in the user's Documents directory
    [Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null
    $rootPassword = [System.Web.Security.Membership]::GeneratePassword(8,0)
    $initFile = Join-Path $myDocs "mysql-init.txt"
    $sqlCMD = "ALTER USER 'root'@'localhost' IDENTIFIED BY '$rootPassword';"
    $sqlCMD  | Out-File -FilePath $initFile -Encoding utf8
    
    # Initialize MySQL with --initialize-insecure
    $htParams = @{
        Path = "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysqld.exe"
        ArgList = @('--initialize-insecure')
        Action = "MySQLInitialize"
    }
    Start-Command @htParams
    
    # Install MySQL as a Windows service
    $htParams = @{
        Path = "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysqld.exe"
        ArgList = @('--install')
        Action = "MySQLInstallService"
    }
    Start-Command @htParams
    
    # Start the MySQL Service
    Start-Service -Name MySQL -Verbose
    
    # Change the root password
    $argList = @()
    $argList += "-uroot"
    $argList += "--execute=`"$sqlCMD`""
    $htParams = @{
        Path = "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysql.exe"
        ArgList = $argList
        Action = "MySQLChangeRootPassword"
    }
    Start-Command @htParams
}
#endregion MySQL Server install

#region Install MySQL Workbench 8.0

# Download and install Microsoft Visual C++ 2015 Redistributable
if ($platform -eq "x64") {
    # 64 bit
    $htParams = @{
        URI = 'https://download.microsoft.com/download/6/D/F/6DF3FF94-F7F9-4F0B-838C-A328D1A7D0EE/vc_redist.x64.exe'
        Name = 'Microsoft Visual C++ 2015 Redistributable Update 3 x64'
    }
} else {
    # 32 bit
    $htParams = @{
        URI = 'https://download.microsoft.com/download/6/D/F/6DF3FF94-F7F9-4F0B-838C-A328D1A7D0EE/vc_redist.x86.exe'
        Name = 'Microsoft Visual C++ 2015 Redistributable Update 3 x86'
    }
}
Install-VCRuntime @htParams

Out-Log -Level Verbose -Message "Installing MySQL Workbench."
Install-Product -Product "Workbench"
#endregion Install MySQL Workbench 8.0

#region Install Connector/NET
Out-Log -Level Verbose -Message "Installing Connector/NET."
Install-Product -Product 'Connector/NET'
#endregion Install Connector/NET

#region Create Database and User
if ($PSBoundParameters.ContainsKey('SkipServer')) {
    Out-Log -Level Info -Message "SkipServer argument specified so local database will not be created."
}
else {
    Out-Log -Level Verbose -Message "Creating csmain local database and csuser account."
    # Create 'csmain' database and 'csuser' user. Grant csuser all privileges to csmain
    $csuserPassword = [System.Web.Security.Membership]::GeneratePassword(8,0)
    $sqlCMD = @"
    CREATE DATABASE IF NOT EXISTS csmain;
    CREATE USER 'csuser'@'localhost' IDENTIFIED BY '$csuserPassword';
    GRANT ALL ON csmain.* TO 'csuser'@'localhost';
"@
    $createFile = Join-Path $myDocs "mysql-create.txt"
    $sqlCMD  | Out-File -FilePath $createFile -Encoding utf8

    $argList = @()
    $argList += "-uroot"
    $argList += "-p$rootPassword"
    $argList += "--execute=`"source $createFile`""
    $htParams = @{
        Path = "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysql.exe"
        ArgList = $argList
        Action = "MySQLCreateDBandUser"
    }
    Start-Command @htParams
}
#endregion Create Database and User

# Stop the stopwatch
$swScript.Stop()
Out-Log -Level Info -Message ("`nScript completed in: {0:g}" -f $swScript.Elapsed)
#endregion Script Body
