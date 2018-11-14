# Downloads the latest CentreStack release and installs on the new machine
<#
.Synopsis
    Downloads the latest CentreStack release and installs on the new machine
.DESCRIPTION
	Downloads the latest CentreStack release and installs on the new machine
.EXAMPLE
    .\Install-CentreStack -Build 6033 -Modules 
.PARAMETER Build
    The build number to download and install
.PARAMETER Modules
    An array of hashtables specifying the name and version of PowerShell modules that will be installed
.NOTES 
    Author: Jeff Reed
    Name: Upgrade-CentreStack.ps1
    Created: 2018-11-14
    
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator


# Enable -Verbose option
#region script parameters
[CmdletBinding()]
Param
(
    [Parameter(
        Mandatory=$true,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The build to download and install."
    )]
    [ValidateScript({
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
        Mandatory=$false,
        ValueFromPipelineByPropertyName=$false,
    )]
	[array]$Modules
)
#endregion script parameters

#region functions
function Disable-InternetExplorerESC {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
    Stop-Process -Name Explorer
    Write-Verbose "IE Enhanced Security Configuration (ESC) has been disabled." 
} #end function Disable-InternetExplorerESC
#endregion functions

#region Script Body
# Disable Internet Explorer Enhanced Security Configuration
Disable-InternetExplorerESC

# Install NuGet package provider
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

# Installing Modules from Azure template 
Foreach ($Module in $Modules) {	
    Find-Module -Name $Module.Name -RequiredVersion $Module.Version -Repository PSGallery -Verbose | Install-Module -Force -Confirm:$false -SkipPublisherCheck -Verbose 
}

# Remove old default modules and install new versions
$DefaultModules = @("PowerShellGet", "PackageManagement","Pester")
Foreach ($Module in $DefaultModules) {
	if ($tmp = Get-Module $Module -ErrorAction SilentlyContinue) {	
        Remove-Module $Module -Force	
    }
	Find-Module -Name $Module -Repository PSGallery -Verbose | Install-Module -Force -Confirm:$false -SkipPublisherCheck -Verbose
}

# Uninstalling old Azure PowerShell Modules
$programName = "Microsoft Azure PowerShell"
$app = Get-WmiObject -Class Win32_Product -Filter "Name Like '$($programName)%'" -Verbose
if ($null -ne $app) {
    $app.Uninstall()
}


# Get the OAuth2 token for the virtual machine's managed identity allowing it to query the Azure Management REST APIs
$uri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F'
$response = Invoke-WebRequest -Uri $uri -Method GET -Headers @{Metadata="true"}
$content = $response.Content | ConvertFrom-Json
$accessToken = $content.access_token

# Use the Azure instance Metadata to get information about this instance
$compute = Invoke-RestMethod -Headers @{"Metadata"="true"} -URI http://169.254.169.254/metadata/instance/compute?api-version=2017-08-01 -Method get
$publicIP = Invoke-RestMethod -Headers @{"Metadata"="true"} -URI "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-08-01&format=text" -Method Get

# Demonstrates how to get information from the Azure REST API for this instance.
$uri = ("https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Compute/virtualMachines/{2}?api-version=2017-12-01" -f $compute.subscriptionId, $compute.resourceGroupName, $compute.name)
$vmInfoRest = (Invoke-WebRequest -Uri $uri  -Method GET -ContentType "application/json" -Headers @{ Authorization ="Bearer $accessToken"}).content | ConvertFrom-JSON
Write-Output ("Instance ID is: {0}" -f $vmInfoRest.id)

# Sign into AzureRM using managed identity
Add-AzureRmAccount -identity
$vmInfoPs = Get-AzureRMVM -ResourceGroupName $compute.resourceGroupName -Name $compute.name
$spID = $vmInfoPs.Identity.PrincipalId
Write-Output ("The managed identity for Azure resources service principal ID is {0}" -f $spID)

Write-Output ("Installing CentreStack build number {0}" -f $Build)
#endregion Script Body