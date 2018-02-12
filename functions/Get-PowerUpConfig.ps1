function Get-PowerUpConfig {
	[CmdletBinding()]
	param
	(
		[string]$FileName
	)
	
	#Read/create configuration
	
	$currentDate = Get-Date
	
	if ($FileName -and (Test-Path $FileName)) {
		$jsonConfig = Get-Content $FileName -Raw | ConvertFrom-Json -ErrorAction Stop
	}
	$config = @{ } | Select-Object ApplicationName, SqlInstance, Database, DeploymentMethod, ConnectionTimeout, ExecutionTimeout, Encrypt, Credential, Username, Password, SchemaVersionTable, Silent, Variables
	
	foreach ($property in $config.psobject.Properties.Name) {
		if ($jsonConfig.$property) {
			$config.$property = $jsonConfig.$property
		}
	}
	
	$config
}