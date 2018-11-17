# Downloads the latest CentreStack release and installs on the new machine
<#
.Synopsis
    Downloads the latest CentreStack release and installs on the new machine
.DESCRIPTION
	Downloads the latest CentreStack release and installs on the new machine
.EXAMPLE
    .\Install-CentreStack -Build 6033 -VaultName kv-centrestack -Modules @(@{name = 'AzureRM.Compute'; version = '5.8.0'}, @{name = 'AzureRM.Profile'; version = '5.8.0'}, @{name = 'AzureRM.KeyVault'; version = '5.2.1'}, @{name = 'AzureAD'; version = '2.0.2.4'})
.PARAMETER Build
    The build number to download and install
.PARAMETER VaultName
    The name of the Azure Key Vault containing secrets for this script.
.PARAMETER Modules
    An array of hashtables specifying the name and version of PowerShell modules that will be installed
.NOTES 
    Author: Jeff Reed
    Name: Upgrade-CentreStack.ps1
    Created: 2018-11-14
    
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator


#region script parameters
[CmdletBinding()]
Param
(
    [Parameter(
        Mandatory = $true,
        ValueFromPipelineByPropertyName = $false,
        HelpMessage = "The build to download and install."
    )]
    [ValidateScript( {
            # Check to ensure string argument is actually all digits
            If ($_ -match "\d+") {
                $True
            }
            else {
                Throw "'$_' is not a valid build number."
            }
        })]        
    [String]
    $Build,

    [Parameter(
        Mandatory = $true,
        ValueFromPipelineByPropertyName = $false,
        HelpMessage = "The name of the Azure Key Vault containing secrets for this script."
    )]
    [ValidateNotNullOrEmpty()]
    [String]
    $VaultName,

    [Parameter(
        Mandatory = $false,
        ValueFromPipelineByPropertyName = $false
    )]
    [array]$Modules
)
#endregion script parameters

#region functions
function Disable-InternetExplorerESC {
    # Disable IE ESC
    Rundll32 iesetup.dll, IEHardenLMSettings, 1, True
    Rundll32 iesetup.dll, IEHardenUser, 1, True
    Rundll32 iesetup.dll, IEHardenAdmin, 1, True
    Update-RegVal -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 -Type "Dword"
    Update-RegVal -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 -Type "Dword"
    Out-Log -Level Info -Message ("IE Enhanced Security Configuration (ESC) has been disabled." )

    # Disable first run wizard
    New-RegKey -KeyPath "HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer"
    New-RegKey -KeyPath "HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\Main"
    Update-RegVal -Path "HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\Main" -Name "DisableFirstRunCustomize" -Value 1 -Type "Dword"
    Out-Log -Level Info -Message ("IE 'Prevent running First Run wizard' policy is enabled." )

} #end function Disable-InternetExplorerESC


#endregion functions

#region Script Body

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

Out-Log -Level Info -Message ("{0} script started on {1}" -f $scriptName, $env:COMPUTERNAME)

# Disable Internet Explorer Enhanced Security Configuration
Disable-InternetExplorerESC

# Install NuGet package provider
Out-Log -Level Info -Message ("Install NuGet package provider")
try {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}
catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Out-Log -Level Warn -Message ("An error occurred while installing the NuGet package provider. Failed item: {0}. Exception Message: {1}" -f $FailedItem, $ErrorMessage)
    Throw $_.exception.message
}


# Installing Modules from Azure template 
Foreach ($Module in $Modules) {	
    Find-Module -Name $Module.Name -RequiredVersion $Module.Version -Repository PSGallery -Verbose | Install-Module -Force -Confirm:$false -SkipPublisherCheck -Verbose 
}

# Uninstalling old Azure PowerShell Modules
$programName = "Microsoft Azure PowerShell"
$app = Get-WmiObject -Class Win32_Product -Filter "Name Like '$($programName)%'" -Verbose
if ($null -ne $app) {
    $app.Uninstall()
}

# Get the OAuth2 token for the virtual machine's managed identity allowing it to query the Azure Management REST APIs
$uri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F'
try {
    $response = Invoke-WebRequest -Uri $uri -Method GET -Headers @{Metadata = "true"}
    $content = $response.Content | ConvertFrom-Json
    $accessToken = $content.access_token
}
catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Out-Log -Level Warn -Message ("An error occurred while retrieving the Azure OAuth2 access token. Failed item: {0}. Exception Message: {1}" -f $FailedItem, $ErrorMessage)
    Throw $_.exception.message
}
# Use the Azure instance Metadata to get information about this instance
try {
    $compute = Invoke-RestMethod -Headers @{"Metadata" = "true"} -URI http://169.254.169.254/metadata/instance/compute?api-version=2017-08-01 -Method get
}
catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Out-Log -Level Warn -Message ("An error occurred while accessing Azure Instance Metadata. Failed item: {0}. Exception Message: {1}" -f $FailedItem, $ErrorMessage)
    Throw $_.exception.message
}

# Demonstrates how to get information from the Azure REST API for this instance.
$uri = ("https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Compute/virtualMachines/{2}?api-version=2017-12-01" -f $compute.subscriptionId, $compute.resourceGroupName, $compute.name)
try {
    $vmInfoRest = (Invoke-WebRequest -Uri $uri  -Method GET -ContentType "application/json" -Headers @{ Authorization = "Bearer $accessToken"}).content | ConvertFrom-JSON
}
catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Out-Log -Level Warn -Message ("An error occurred while accessing the Azure REST API. Failed item: {0}. Exception Message: {1}" -f $FailedItem, $ErrorMessage)
    Throw $_.exception.message
}

Out-Log -Level Info -Message ("Instance ID is: {0}" -f $vmInfoRest.id)

# Sign into AzureRM using managed identity
Add-AzureRmAccount -identity
$vmInfoPs = Get-AzureRMVM -ResourceGroupName $compute.resourceGroupName -Name $compute.name
$spID = $vmInfoPs.Identity.PrincipalId
Out-Log -Level Info -Message ("The managed identity for Azure resources service principal ID is {0}" -f $spID)

Write-Output ("Installing CentreStack build number {0}" -f $Build)
$adminVMUsername = (Get-AzureKeyVaultSecret -VaultName $VaultName -SecretName 'adminVMUsername').SecretValueText
$adminVMPassword = (Get-AzureKeyVaultSecret -VaultName $VaultName -SecretName 'adminVMPassword').SecretValueText
# Get a secure string for the password of the VM's local administrator
$vmPassword = ConvertTo-SecureString -String $adminVMPassword -AsPlainText -Force
# Get a credential object for the VM's local administrator
$vmAdminCred = New-Object PSCredential $adminVMUsername, $vmPassword

$adminDBUsername = (Get-AzureKeyVaultSecret -VaultName $VaultName -SecretName 'adminDBUsername').SecretValueText
$adminDBPassword = (Get-AzureKeyVaultSecret -VaultName $VaultName -SecretName 'adminDBPassword').SecretValueText
$databaseHost = (Get-AzureKeyVaultSecret -VaultName $VaultName -SecretName 'databaseHost').SecretValueText
switch ($databaseHost) {
    "Local" {
        <#
        $sb = Join-Path $scriptDir "Install-MySQL.ps1"
        $scriptBlock = [scriptblock]::Create($sb)
        $job = Start-Job -scriptBlock $scriptBlock -Credential $vmAdminCred
        $job | Wait-Job | Receive-Job
        #>
        $exePath = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        $scriptPath = Join-Path $scriptDir "Install-MySQL.ps1"
        $runAsArgs = "-NonInteractive -File `"$scriptPath`"
        Invoke-Runas -User $adminVMUsername -Password $adminVMPassword -Binary $exePath -Args $runAsArgs -LogonType 0x1
    }
    "Azure_SQL" { Out-Log -Level Info -Message "Using Azure SQL."}
    "Azure_MySQL" { Out-Log -Level Info -Message "Using Azure MySQL."}
    "None" {Out-Log -Level Info -Message "No database specified."}
}
#endregion Script Body