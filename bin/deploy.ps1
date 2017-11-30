[CmdletBinding()]
Param (
	[string]$SqlInstance,
	[string]$Database,
	[ValidateSet('SingleTransaction', 'TransactionPerScript', 'NoTransaction')]
	[string]$DeploymentMethod = 'NoTransaction',
	[int]$ConnectionTimeout,
	[switch]$Encrypt,
	[pscredential]$Credential,
	[string]$UserName,
	[securestring]$Password,
	[string]$LogToTable,
	[switch]$Silent,
	[hashtable]$Variables
)

#Stop on error
#$ErrorActionPreference = 'Stop'

#Import module
If (Get-Module PowerUp) {
	Remove-Module PowerUp
}
Import-Module "$PSScriptRoot\Modules\PowerUp\PowerUp.psd1" -Force

#Invoke deployment using current parameters
$params = $PSBoundParameters
$params += @{ PackageFile = "$PSScriptRoot\PowerUp.package.json"}
Invoke-PowerUpDeployment @params

