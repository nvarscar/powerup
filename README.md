| master | [![Build status](https://ci.appveyor.com/api/projects/status/m0ml0392r631tp60/branch/master?svg=true)](https://ci.appveyor.com/project/nvarscar/powerup/branch/master) |
| development | [![Build status](https://ci.appveyor.com/api/projects/status/m0ml0392r631tp60/branch/development?svg=true)](https://ci.appveyor.com/project/nvarscar/powerup/branch/development) |

# PowerUp
PowerUp is a Powershell module that provides SQL script deployment capabilities. It organizes scripts into builds and then deploys them in a repeatable manner into the database of your choice ensuring that all builds are deployed in proper order and only once.

The module is built around [DbUp](https://github.com/DbUp/DbUp) .Net library, which provides flexibility and reliability during deployments. 

## Features
The most notable features of the module:

* No scripting experience required - the module is designed around usability and functionality
* Will aggregate source scripts from multiple sources into a single ready-to-deploy file
* Can detect new/changed files in your source code folder and generate a new build out of them
* Reliably deploys the scripts in a consistent manner - all the scripts are executed in alphabetical order one build at a time
* Can be deployed without the module installed in the system - module itself is integrated into the deployment package
* Introduces optional internal build system: older builds are kept inside the deployment package ensuring smooth and errorless deployments
* Transactionality of the deployments/migrations: every build can be deployed as a part of a single transaction, rolling back unsuccessful deployments
* Dynamically change your code based on custom variables - use `#{customVarName}` tokens to define variables inside the scripts or execution parameters
* Packages are fully compatible with Octopus Deploy deployments: all packages are in essence zip archives with Deploy.ps1 file that initiates deployment

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
# Quick deployment
New-PowerUpPackage Deploy.zip -ScriptPath C:\temp\myscripts | Install-PowerUpPackage -SqlInstance server1 -Database MyDB

# Adding builds to the package
Add-PowerUpBuild Deploy.zip -ScriptPath C:\temp\myscripts -UniqueOnly -Build 2.0
Get-ChildItem C:\temp\myscripts\v3 | Add-PowerUpBuild Deploy.zip -NewOnly -Build 3.0

# Setting deployment options within the package to be able to deploy it without specifying options
Update-PowerUpConfig Deploy.zip -Values @{ DeploymentMethod = 'SingleTransaction'; SqlInstance = 'localhost'; DatabaseName = 'MyDb2' }
Install-PowerUpPackage Deploy.zip
```