function Invoke-PowerUpDeployment {
	<#
	.SYNOPSIS
		Deploys extracted PowerUp package from the specified location
	
	.DESCRIPTION
		Mostly intended for internal use, deploys an extracted PowerUp package with optional parameters. 
		Uses a table specified in SchemaVersionTable parameter to determine scripts to run.
		Will deploy all the builds from the package that previously have not been deployed.
	
	.PARAMETER PackageFile
		Path to the PowerUp package file (usually, PowerUp.package.json).
	
	.PARAMETER SqlInstance
		Database server to connect to. SQL Server only for now.
		Aliases: Server, SQLServer, DBServer, Instance
	
	.PARAMETER Database
		Name of the database to execute the scripts in. Optional - will use default database if not specified.
	
	.PARAMETER DeploymentMethod
		Choose one of the following deployment methods:
		- SingleTransaction: wrap all the deployment scripts into a single transaction and rollback whole deployment on error
		- TransactionPerScript: wrap each script into a separate transaction; rollback single script deployment in case of error
		- NoTransaction: deploy as is
		
		Default: NoTransaction
	
	.PARAMETER ConnectionTimeout
		Database server connection timeout in seconds. Only affects connection attempts. Does not affect execution timeout.
		If 0, will wait for connection until the end of times.
		
		Default: 30
		
	.PARAMETER ExecutionTimeout
		Script execution timeout. The script will be aborted if the execution takes more than specified number of seconds.
		If 0, the script is allowed to run until the end of times.

		Default: 180
	
	.PARAMETER Encrypt
		Enables connection encryption.
	
	.PARAMETER Credential
		PSCredential object with username and password to login to the database server.
	
	.PARAMETER UserName
		An alternative to -Credential - specify username explicitly
	
	.PARAMETER Password
		An alternative to -Credential - specify password explicitly
	
	.PARAMETER SchemaVersionTable
		A table that will hold the history of script execution. This table is used to choose what scripts are going to be 
		run during the deployment, preventing the scripts from being execured twice.
		If set to $null, the deployment will not be tracked in the database. That will also mean that all the scripts 
		and all the builds from the package are going to be deployed regardless of any previous deployment history.

		Default: dbo.SchemaVersions
	
	.PARAMETER Silent
		Will supress all output from the command.
	
	.PARAMETER Variables
		Hashtable with variables that can be used inside the scripts and deployment parameters.
		Proper format of the variable tokens is #{MyVariableName}
		Can also be provided as a part of Configuration hashtable: -Configuration @{ Variables = @{ Var1 = ...; Var2 = ...}}
		Will augment and/or overwrite Variables defined inside the package.

	.PARAMETER OutputFile
		Log output into specified file.
	
	.PARAMETER Append
		Append output to the -OutputFile instead of overwriting it.

	.PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
		# Start the deployment of the extracted package from the current folder
		Invoke-PowerUpDeployment
	
	.EXAMPLE
		# Start the deployment of the extracted package from the current folder using specific connection parameters
		Invoke-PowerUpDeployment -SqlInstance 'myserver\instance1' -Database 'MyDb' -ExecutionTimeout 3600 
		
	.EXAMPLE
		# Start the deployment of the extracted package using custom logging parameters and schema tracking table
		Invoke-PowerUpDeployment .\Extracted\PowerUp.package.json -SchemaVersionTable dbo.SchemaHistory -OutputFile .\out.log -Append
	
	.EXAMPLE
		# Start the deployment of the extracted package in the current folder using variables instead of specifying values directly
		Invoke-PowerUpDeployment -SqlInstance '#{server}' -Database '#{db}' -Variables @{server = 'myserver\instance1'; db = 'MyDb'}
#>
	
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[string]$PackageFile = ".\PowerUp.package.json",
		[Alias('Server', 'SqlServer', 'DBServer', 'Instance')]
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
		[AllowNull()]
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
	$config = [PowerUpConfig]::FromFile($configPath)
	
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
		$config.$property = Resolve-VariableToken $config.$property $runtimeVariables
	}
	
	#Apply overrides if any
	foreach ($key in ($PSBoundParameters.Keys | Where-Object { $_ -ne 'Variables' })) {
		if ($key -in $config.psobject.Properties.Name) {
			$config.$key = Resolve-VariableToken $PSBoundParameters[$key] $runtimeVariables
		}
	}
	
	#Apply default values if not set
	if (!$config.ApplicationName) { $config.ApplicationName = 'PowerUp' }
	if (!$config.SqlInstance) { $config.SqlInstance = 'localhost' }
	if ($config.ConnectionTimeout -like '') { $config.ConnectionTimeout = 30 }
	if ($config.ExecutionTimeout -like '') { $config.ConnectionTimeout = 180 }
	
	
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
			$scriptContent = Resolve-VariableToken (Get-Content $scriptPath -Raw) $runtimeVariables
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
	$dbUp = [StandardExtensions]::LogTo($dbUp, [PowerUpLog]::new($config.Silent, $OutputFile, $Append))
	$dbUp = [StandardExtensions]::LogScriptOutput($dbUp)
	
	# Configure schema versioning
	if (!$config.SchemaVersionTable) {
		$dbUp = [StandardExtensions]::JournalTo($dbUp,([DbUp.Helpers.NullJournal]::new()))
	}
	elseif ($config.SchemaVersionTable) {
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
	if ($PSCmdlet.ShouldProcess($package, "Deploying the package")) {
		$build = $dbUp.Build()
		$upgradeResult = $build.PerformUpgrade() 
		$upgradeResult
	}
}
