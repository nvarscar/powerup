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
	$config = @{ } | Select-Object ApplicationName, Build, SqlInstance, Database, DeploymentMethod, ConnectionTimeout, Encrypt, Credential, Username, Password, SchemaVersionTable, Silent, Variables
	$config.Build = [string]$currentDate.Year + '.' + [string]$currentDate.Month + '.' + [string]$currentDate.Day + '.' + [string]$currentDate.Hour + [string]$currentDate.Minute + [string]$currentDate.Second
	#$config.SqlInstance = 'localhost'
	#$config.ConnectionTimeout = 30
	#$config.LogToTable = 'dbo.SchemaVersions'
	
	foreach ($property in $config.psobject.Properties.Name) {
		if ($jsonConfig.$property) {
			$config.$property = $jsonConfig.$property
		}
	}
	
	$config
}