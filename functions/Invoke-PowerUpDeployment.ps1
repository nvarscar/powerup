function Invoke-PowerUpDeployment {
	<#
	.SYNOPSIS
		Deploys extracted PowerUp package from the specified location
	
	.DESCRIPTION
		A detailed description of the Invoke-PowerUpPackage function.
	
	.EXAMPLE
				PS C:\> Invoke-PowerUpPackage
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()]
	Param (
		[string]$PackageFile = ".\PowerUp.package.json",
		[string]$SqlInstance,
		[string]$Database,
		[ValidateSet('SingleTransaction', 'TransactionPerScript', 'NoTransaction')]
		[string]$DeploymentMethod = 'NoTransaction',
		[int]$ConnectionTimeout,
		[int]$ExecutionTimeout,
		[switch]$Encrypt,
		[pscredential]$Credential,
		[string]$UserName,
		[securestring]$Password,
		[string]$SchemaVersionTable,
		[switch]$Silent,
		[string]$OutputFile,
		[switch]$Append,
		[hashtable]$Variables
	)
	
	#Get package object from the json file
	if (!(Test-Path $PackageFile)) {
		throw "Package file $PackageFile not found. Aborting deployment."
	}
	else {
		$pFile = Get-Item $PackageFile
	}
	Write-Verbose "Loading package information from $pFile"
	$package = [PowerUpPackage]::FromFile($pFile.FullName)
	
	#Read config file 
	$configPath = Join-Path $pFile.DirectoryName $package.ConfigurationFile
	if (!$package.ConfigurationFile -or !(Test-Path $configPath)) {
		throw "Configuration file cannot be found. The package is corrupted."
	}
	$config = Get-PowerUpConfig $configPath
	
	#Join variables from config and parameters
	$runtimeVariables = @{ }
	if ($Variables) {
		$runtimeVariables += $Variables
	}
	if ($config.Variables) {
		foreach ($variable in $config.Variables.psobject.Properties.Name) {
			if ($variable -notin $runtimeVariables.Keys) {
				$runtimeVariables += @{
					$variable = $config.Variables.$variable
				}
			}
		}
	}
	
	#Replace tokens if any
	foreach ($property in $config.psobject.Properties.Name | Where-Object { $_ -ne 'Variables' }) {
		$config.$property = Replace-VariableTokens $config.$property $runtimeVariables
	}
	
	#Apply overrides if any
	foreach ($key in ($PSBoundParameters.Keys | Where-Object { $_ -ne 'Variables' })) {
		if ($key -in $config.psobject.Properties.Name) {
			$config.$key = Replace-VariableTokens $PSBoundParameters[$key] $runtimeVariables
		}
	}
	
	#Apply default values if not set
	if (!$config.ApplicationName) { $config.ApplicationName = 'PowerUp' }
	if (!$config.SqlInstance) { $config.SqlInstance = 'localhost' }
	if ($config.ConnectionTimeout -like '') { $config.ConnectionTimeout = 30 }
	if ($config.ExecutionTimeout -like '') { $config.ConnectionTimeout = 180 }
	if (!$config.SchemaVersionTable) { $config.SchemaVersionTable = 'dbo.SchemaVersions' }
	
	
	#Build connection string
	$CSBuilder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder
	$CSBuilder["Server"] = $config.SqlInstance
	if ($config.Database) { $CSBuilder["Database"] = $config.Database }
	if ($config.Encrypt) { $CSBuilder["Encrypt"] = $true }
	$CSBuilder["Connection Timeout"] = $config.ConnectionTimeout
	
	if ($config.Credential) {
		$CSBuilder["Trusted_Connection"] = $false
		$CSBuilder["User ID"] = $config.Credential.UserName
		$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($config.Credential.Password)
		$CSBuilder["Password"] = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
	}
	elseif ($config.Username) {
		$CSBuilder["Trusted_Connection"] = $false
		$CSBuilder["User ID"] = $config.UserName
		if ($config.Password.GetType() -eq [securestring]) {
			$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($config.Password)
			$CSBuilder["Password"] = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
		}
		else {
			$CSBuilder["Password"] = $config.Password
		}
	}
	else {
		$CSBuilder["Integrated Security"] = $true
	}
	
	$CSBuilder["Application Name"] = $config.ApplicationName
	
	
	$scriptCollection = @()
	$scriptRoot = Join-Path $pFile.DirectoryName $package.ScriptDirectory
	
	# Get contents of the script files
	foreach ($build in $package.builds) {
		foreach ($script in $build.scripts) {
			# Replace tokens in the scripts
			$scriptPath = Join-Path $scriptRoot $script.PackagePath
			$scriptContent = Replace-VariableTokens (Get-Content $scriptPath -Raw)
			$scriptCollection += [DbUp.Engine.SqlScript]::new($script.PackagePath, $scriptContent)
		}
	}
	
	#Build dbUp object
	$dbUp = [DbUp.DeployChanges]::To
	$dbUp = [SqlServerExtensions]::SqlDatabase($dbUp, $CSBuilder.ToString())
	
	#Add deployment scripts to the object
	$dbUp = [StandardExtensions]::WithScripts($dbUp, $scriptCollection)
	
	
	if ($config.DeploymentMethod -eq 'SingleTransaction') {
		$dbUp = [StandardExtensions]::WithTransaction($dbUp)
	}
	elseif ($config.DeploymentMethod -eq 'TransactionPerScript') {
		$dbUp = [StandardExtensions]::WithTransactionPerScript($dbUp)
	}
	
	# Enable logging using PowerUpConsoleLog class implementing a logging Interface
	$dbUp = [StandardExtensions]::LogTo($dbUp, [PowerUpLog]::new($Silent, $OutputFile, $Append))
	$dbUp = [StandardExtensions]::LogScriptOutput($dbUp)
	
	# Configure schema versioning
	if ($config.SchemaVersionTable) {
		$table = $config.SchemaVersionTable.Split('.')
		if (($table | Measure-Object).Count -gt 2) {
			throw 'Incorrect table name - use the following syntax: schema.table'
		}
		elseif (($table | Measure-Object).Count -eq 2) {
			$tableName = $table[1]
			$schemaName = $table[0]
		}
		elseif (($table | Measure-Object).Count -eq 1) {
			$tableName = $table[0]
			$schemaName = 'dbo'
		}
		else {
			throw 'No table name specified'
		}
		
		$dbUp = [SqlServerExtensions]::JournalToSqlTable($dbUp, $schemaName, $tableName)
	}

	#Adding execution timeout - defaults to 180 seconds
	$dbUp = [StandardExtensions]::WithExecutionTimeout($dbUp, [timespan]::FromSeconds($config.ExecutionTimeout))

	#Build and Upgrade
	$build = $dbUp.Build()
	
	#try {
	$upgradeResult = $build.PerformUpgrade() <#*>&1 | ForEach-Object {
		$record = $_
		switch ($_.GetType().Name) {
			ErrorRecord {
				Write-Error $record 
			}
			WarningRecord {
				Write-Warning $record
			}
			InformationRecord {
				Write-Host $record
			}
			default {
				$record
			}
		}
	}
	#>
	#}
	#	catch {
	#		Write-Host "Gotcha!"
	#		#throw $_	
	#	}
	$upgradeResult
	
	
	#TODO: Place script here
}
