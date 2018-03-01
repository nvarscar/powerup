| master | development |
|---|---|
| [![Build status](https://ci.appveyor.com/api/projects/status/m0ml0392r631tp60/branch/master?svg=true)](https://ci.appveyor.com/project/nvarscar/powerup/branch/master) | [![Build status](https://ci.appveyor.com/api/projects/status/m0ml0392r631tp60/branch/development?svg=true)](https://ci.appveyor.com/project/nvarscar/powerup/branch/development) |

# PowerUp
PowerUp is a Powershell module that provides SQL script deployment capabilities. It organizes scripts into builds and then deploys them in a repeatable manner into the database of your choice ensuring that all builds are deployed in proper order and only once.

The module is built around [DbUp](https://github.com/DbUp/DbUp) .Net library, which provides flexibility and reliability during deployments. 

Currently supported RDBMS:
* SQL Server

## Features
The most notable features of the module:

* No scripting experience required - the module is designed around usability and functionality
* Introduces an option to aggregate source scripts from multiple sources into a single ready-to-deploy file
* Can detect new/changed files in your source code folder and generate a new build out of them
* Reliably deploys the scripts in a consistent manner - all the scripts are executed in alphabetical order one build at a time
* Can be deployed without the module installed in the system - module itself is integrated into the deployment package
* Introduces optional internal build system: older builds are kept inside the deployment package ensuring smooth and errorless deployments
* Transactionality of the deployments/migrations: every build can be deployed as a part of a single transaction, rolling back unsuccessful deployments
* Dynamically change your code based on custom variables - use `#{customVarName}` tokens to define variables inside the scripts or execution parameters
* Packages are fully compatible with Octopus Deploy deployments: all packages are in essence zip archives with Deploy.ps1 file that initiates deployment


## System requirements

* Powershell 5.0 or higher

## Installation
```powershell
git clone https://github.com/nvarscar/powerup.git
Import-Module .\PowerUp
```

## Usage scenarios

* Ad-hoc deployments of any scale without the necessity of executing the code manually
* Delivering new version of the database schema in a consistent manner to multiple environments
* Build/Test/Deploy stage inside of Continuous Integration/Continuous Delivery pipelines
* Dynamic deployment based on modified files in the source folder

## Examples

```powershell
# Quick deployment without tracking deployment history
Invoke-PowerUpDeployment -ScriptPath C:\temp\myscripts -SqlInstance server1 -Database MyDB -SchemaVersionTable $null

# Deployment using packages & builds with keeping track of deployment history in dbo.SchemaVersions
New-PowerUpPackage Deploy.zip -ScriptPath C:\temp\myscripts | Install-PowerUpPackage -SqlInstance server1 -Database MyDB

# Create new deployment package with predefined configuration and deploy it replacing #{dbName} tokens with corresponding values
New-PowerUpPackage -Path MyPackage.zip -ScriptPath .\Scripts -Configuration @{ Database = '#{dbName}'; ConnectionTimeout = 5 }
Install-PowerUpPackage MyPackage.zip -Variables @{ dbName = 'myDB' }

# Adding builds to the package
Add-PowerUpBuild Deploy.zip -ScriptPath .\myscripts -Type Unique -Build 2.0
Get-ChildItem .\myscripts | Add-PowerUpBuild Deploy.zip -Type New,Modified -Build 3.0

# Setting deployment options within the package to be able to deploy it without specifying options
Update-PowerUpConfig Deploy.zip -Configuration @{ DeploymentMethod = 'SingleTransaction'; SqlInstance = 'localhost'; DatabaseName = 'MyDb2' }
Install-PowerUpPackage Deploy.zip

# Generating config files and using it later as a deployment template
(Get-PowerUpConfig -Configuration @{ DeploymentMethod = 'SingleTransaction'; SqlInstance = 'devInstance'; DatabaseName = 'MyDB' }).SaveToFile('.\dev.json')
(Get-PowerUpConfig -Path '.\dev.json' -Configuration @{ SqlInstance = 'prodInstance' }).SaveToFile('.\prod.json')
Install-PowerUpPackage Deploy.zip -ConfigurationFile .\dev.json

# Install package using internal script Deploy.ps1 - useable when module is not installed locally
Expand-Archive Deploy.zip '.\MyTempFolder'
.\MyTempFolder\Deploy.ps1 -SqlInstance server1 -Database MyDB
```

## Planned for future releases

* Code analysis: know what kind of code makes its way into the package. Will find hidden sysadmin grants, USE statements and other undesired statements
* Support for other RDBMS (eventually, everything that DbUp libraries can talk with)
* Integration with unit tests (tSQLt/Pester/...?)
* Module for Ansible (right now can still be used as a powershell task)
* Linux support
* SQLCMD support