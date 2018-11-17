<#
	.SYNOPSIS    
		This script contains functions that are intended to be dot-sourced by other scripts.
	.NOTES    
		File Name  : CommonFunctions.ps1    
		Author     : Jeff Reed - jeff.reed@citrix.com
		Requires   : PowerShell Version 3.0
	.EXAMPLE    
		PS [C:\foo]: .\CommonFunctions.ps1
#>

#Requires -Version 3.0
#region functions
function Out-Log {
    <#  
    .SYNOPSIS
        Writes output to the log file.
    .DESCRIPTION
        Writes output the Host and appends output to the log file with date/timestamp
    .PARAMETER Message
        The string that will be output to the log file
    .PARAMETER Level
        One of: "Info", "Warn", "Error", "Verbose"
    .NOTES    
        Requires that the $Script:log variable be set by the caller
    .EXAMPLE
        Out-Log "Test to write to log"
    .EXAMPLE
        Out-Log -Message "Test to write to log" -Level "Info"
    #>

    [CmdletBinding()]
    param (
        [Parameter (
            Position = 0, 
            Mandatory = $true,
            ValueFromPipeline = $False,
            ValueFromPipelineByPropertyName = $False
        ) ]
        [string] $Message,
        [Parameter (
            Position = 1, 
            Mandatory = $false,
            ValueFromPipeline = $False,
            ValueFromPipelineByPropertyName = $False
        ) ]
        [ValidateSet("Info", "Warn", "Error", "Verbose")]
        [string] $Level = "Info"
    )
	
    $ts = $(Get-Date -format "s")
    $s = ("{0}`t{1}`t{2}" -f $ts, $Level, $Message)
    if ($Level -eq "Verbose") {
        # Only log and output if script is called with -Verbose common parameter
        if ( $VerbosePreference -ne [System.Management.Automation.ActionPreference]::SilentlyContinue ) {
            Write-Output $s
            Write-Output $s | Out-File -FilePath $script:log -Encoding utf8 -Append
        }
    } 
    else {
        Write-Output $s
        Write-Output $s | Out-File -FilePath $script:log -Encoding utf8 -Append
    }
} #end function Out-Log

function New-RegKey {
    <#
    .SYNOPSIS
        Creates registry key if it does not exist
    .DESCRIPTION
        Creates registry key if it does not exist
    .EXAMPLE
        New-Key -KeyPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AeDebug"
    .PARAMETER KeyPath
        The registry key that will be created if it does not exist
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $false)]
        [string] $KeyPath
    )

    # Creates registry key if it does not exist
    if (-not (Test-Path $KeyPath)) {
        New-Item $KeyPath -Verbose | Out-Null
    } 
} # end function New-RegKey

function Update-RegVal {
    <#
    .SYNOPSIS
        Updates an existing registry value or creates a new value if it doesn't exist
    .DESCRIPTION
        Updates an existing registry value or creates a new value if it doesn't exist
    .EXAMPLE
        Update-RegVal -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AeDebug" -Name "Auto" -Value "1" -Type "String"
    .PARAMETER Path
        The registry key 
    .PARAMETER Name
        The name of the registry value
    .PARAMETER Value
        The value data of the registry value
    .PARAMETER Type
        The data type, either DWORD or String
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $false)]
        [string] $Path,
        
        [Parameter(Mandatory = $true, ValueFromPipeline = $false)]
        [string] $Name,
        
        [Parameter(Mandatory = $true, ValueFromPipeline = $false)] 
        [string] $Value,
        
        [Parameter(Mandatory = $true, ValueFromPipeline = $false)]
        [ValidateSet("DWord", "String")]
        [string] $Type

    )    
 
    $key = Get-Item -LiteralPath $Path
    if ($null -eq $key.GetValue($Name, $null)) {
        # Create the value as it doesn't currently exist
        New-ItemProperty -path $Path -name $Name -value $Value -PropertyType $Type -Verbose | Out-Null
    }
    else {
        # Value exists, update it
        Set-ItemProperty -path $Path -name $Name -value $Value -Verbose
    }
} # end function Update-RegVal

function Invoke-Runas {

    <#
    .SYNOPSIS
        Overview:

        Functionally equivalent to Windows "runas.exe", using Advapi32::CreateProcessWithLogonW (also used
        by runas under the hood).
    .DESCRIPTION
        Author: Ruben Boonen (@FuzzySec)
        License: BSD 3-Clause
        Required Dependencies: None
        Optional Dependencies: None
    .PARAMETER User
        Specify the username
    .PARAMETER Password
        Specify password.
    .PARAMETER Domain
        Specify domain. Defaults to localhost if not specified.
    .PARAMETER LogonType
        dwLogonFlags:
            0x00000001 --> LOGON_WITH_PROFILE
                            Log on, then load the user profile in the HKEY_USERS registry
                            key. The function returns after the profile is loaded.
                            
            0x00000002 --> LOGON_NETCREDENTIALS_ONLY (= /netonly)
                            Log on, but use the specified credentials on the network only.
                            The new process uses the same token as the caller, but the
                            system creates a new logon session within LSA, and the process
                            uses the specified credentials as the default credentials.
    .PARAMETER Binary
        Full path of the module to be executed.
    .PARAMETER Args
        Arguments to pass to the module, e.g. "/c calc.exe". Defaults to $null if not specified.
    .EXAMPLE
        Start cmd with a local account
        C:\PS> Invoke-Runas -User SomeAccount -Password SomePass -Binary C:\Windows\System32\cmd.exe -LogonType 0x1
        
    .EXAMPLE
        Start cmd with remote credentials. Equivalent to "/netonly" in runas.
        C:\PS> Invoke-Runas -User SomeAccount -Password SomePass -Domain SomeDomain -Binary C:\Windows\System32\cmd.exe -LogonType 0x2
    #>
    
    param (
        [Parameter(Mandatory = $True)]
        [string]$User,

        [Parameter(Mandatory = $True)]
        [string]$Password,

        [Parameter(Mandatory = $False)]
        [string]$Domain=".",

        [Parameter(Mandatory = $True)]
        [string]$Binary,

        [Parameter(Mandatory = $False)]
        [string]$Args=$null,

        [Parameter(Mandatory = $True)]
        [int][ValidateSet(1,2)]
        [string]$LogonType
    )  
    
    Add-Type -TypeDefinition @"
    using System;
    using System.Diagnostics;
    using System.Runtime.InteropServices;
    using System.Security.Principal;
    
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public uint dwProcessId;
        public uint dwThreadId;
    }
    
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO
    {
        public uint cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public uint dwX;
        public uint dwY;
        public uint dwXSize;
        public uint dwYSize;
        public uint dwXCountChars;
        public uint dwYCountChars;
        public uint dwFillAttribute;
        public uint dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }
    
    public static class Advapi32
    {
        [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
        public static extern bool CreateProcessWithLogonW(
            String userName,
            String domain,
            String password,
            int logonFlags,
            String applicationName,
            String commandLine,
            int creationFlags,
            int environment,
            String currentDirectory,
            ref  STARTUPINFO startupInfo,
            out PROCESS_INFORMATION processInformation);
    }
    
    public static class Kernel32
    {
        [DllImport("kernel32.dll")]
        public static extern uint GetLastError();
    }
"@
        
    # StartupInfo Struct
    $StartupInfo = New-Object STARTUPINFO
    $StartupInfo.dwFlags = 0x00000001
    $StartupInfo.wShowWindow = 0x0001
    $StartupInfo.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($StartupInfo)
    
    # ProcessInfo Struct
    $ProcessInfo = New-Object PROCESS_INFORMATION
    
    # CreateProcessWithLogonW --> lpCurrentDirectory
    $GetCurrentPath = (Get-Item -Path ".\" -Verbose).FullName
    
    Write-Verbose "Calling Advapi32::CreateProcessWithLogonW"
    $CallResult = [Advapi32]::CreateProcessWithLogonW(
        $User, $Domain, $Password, $LogonType, $Binary,
        $Args, 0x04000000, $null, $GetCurrentPath,
        [ref]$StartupInfo, [ref]$ProcessInfo)
    
    if (!$CallResult) {
        $exception = $((New-Object System.ComponentModel.Win32Exception([int][Kernel32]::GetLastError())).Message) 
        $message = ("[Something went wrong! GetLastError returned: {0}" -f $exception)
        Out-Log -Message $message -Level Error
        Throw $exception
    } else {
        Write-Verbose "Success, process details:"
        Get-Process -Id $ProcessInfo.dwProcessId
    }
}
   
#endregion functions