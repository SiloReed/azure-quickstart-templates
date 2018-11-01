# Install CentreStack on Windows Server

CentreStack is your "file server in the cloud"

This Template **101-vm-centrestack** builds the following:

* Creates a Public IP Address
* Creates a Virtual Network
* Creates 1 Nic for the Virtual Machine
* Creates 1 Virtual Machine with OS Disk with Windows 2016
* Creates an Azure SQL Standard instance
* Creates an Azure SQL database named 'csmain'
* Installs CentreStack

## Usage

Click on the **Deploy to Azure** button below. This will open the Azure Portal (login if necessary) and start a Custom Deployment. The following Parameters will be shown and must be updated / selected accordingly.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2Fazure-quickstart-templates%2Fmaster%2F101-vm-centrestack%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2Fazure-quickstart-templates%2Fmaster%2F101-vm-centrestack%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

## Parameters

* dnsNameForPublicIP
  The DNS Name for the Public IP Address. e.g. pipnameexample-dev.

* adminUsername
  The name of the Administrator Account to be used to access the CentreStack server.

* adminSQLUsername
  The name of the Azure SQL Administrator Account to be used to access the Azure SQL instance.
* vmAdminPassword
  The password for the Admin Account. Must be at least 12 characters long.

* vmSize
  The size of VM required.
  Default is Standard_D1_v2 unless overridden.

* vmName
  The name of the CentreStack virtual machine

* serverNameSQL
  The base name of the Azure SQL Server instance. The actual name will be a lower case unique string.

* storageAccountsDiagName
  The base name of the storage account for diagnostics. The actual name will be a lower case unique string.

* storageAccountsDisksName
  The base name of the storage account for boot disks. The actual name will be a lower case unique string.

* storageAccountsBlobName

* _artifactsLocation
  Storage account name to receive post-build staging folder upload.
* _artifactsLocationSasToken
  SAS token to access Storage account name

## Prerequisites

Access to Azure

## Versioning

We use [Github](https://github.com/) for version control.

## Authors

**Jeff Reed** - *Initial work* - [vm-centrestack](https://github.com/azure-quickstart-templates/101-vm-centrestack)