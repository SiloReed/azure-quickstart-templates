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
#endregion functions