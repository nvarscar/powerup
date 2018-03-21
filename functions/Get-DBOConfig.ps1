function Get-DBOConfig {
	<#
	.SYNOPSIS
	Returns a PowerUpConfig object
	
	.DESCRIPTION
	Returns a PowerUpConfig object from an existing json file. If file was not specified, returns a blank PowerUpConfig object.
	Values of the config can be overwritten by the hashtable parameter -Configuration.
	
	.PARAMETER Path
	Path to the JSON config file.
		
	.PARAMETER Configuration
	Overrides for the configuration values. Will replace existing configuration values.

	.PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
	# Returns empty configuration
	Get-DBOConfig
	
	.EXAMPLE
	# Returns configuration from existing file
	Get-DBOConfig c:\package\powerup.config.json

	.EXAMPLE
	# Saves empty configuration to a file
	(Get-DBOConfig).SaveToFile('c:\package\powerup.config.json')

	#>
	[CmdletBinding()]
	param
	(
		[string]$Path,
		[hashtable]$Configuration
	)
	if ($Path) {
		Write-Verbose "Reading configuration from $Path"
		$config = [PowerUpConfig]::FromFile($Path)
	}
	else {
		Write-Verbose "Generating blank configuration object"
		$config = [PowerUpConfig]::new()
	}
	if ($Configuration) {
		Write-Verbose "Overwriting configuration keys $($Configuration.Keys -join ', ') with new values"
		foreach ($property in $Configuration.Keys) {
			$config.SetValue($property, $Configuration.$property)
		}
	}
	$config
}