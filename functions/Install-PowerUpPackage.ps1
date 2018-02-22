function Install-PowerUpPackage {
	<#
	.SYNOPSIS
		Deploys an existing PowerUp package
	
	.DESCRIPTION
		Deploys an existing PowerUp package with optional parameters. 
		Uses a table specified in SchemaVersionTable parameter to determine scripts to run.
		Will deploy all the builds from the package that previously have not been deployed.
	
	.PARAMETER Path
		Path to the existing PowerUpPackage.
		Aliases: Name, FileName, Package
	
	.PARAMETER WorkSpace
		Optional folder to unzip the package to. Will hold the extracted package after completion.
	
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
		A table that will hold the history of script execution.

		Default: dbo.SchemaVersions
	
	.PARAMETER Silent
		Will supress all output from the command.
	
	.PARAMETER Variables
		Hashtable with variables that can be used inside the scripts and deployment parameters.
		Proper format of the variable tokens is #{MyVariableName}
		Can also be provided as a part of Configuration hashtable: -Configuration @{ Variables = @{ Var1 = ...; Var2 = ...}}
		Will augment and/or overwrite Variables defined inside the package.
	
	.PARAMETER Force
		Will overwrite contents of -WorkSpace folder if it is not empty.
	
	.PARAMETER SkipValidation
		Skip validation of the package that ensures the integrity of all the files and builds.
	
	.PARAMETER OutputFile
		Log output into specified file.
	
	.PARAMETER Append
		Append output to the -OutputFile instead of overwriting it.

	.PARAMETER ConfigurationFile
		A path to the custom configuration json file
	
	.PARAMETER Configuration
		Hashtable containing necessary configuration items. Will override parameters in ConfigurationFile
	
	.PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
		# Installs package with predefined configuration inside the package
		Install-PowerUpPackage .\MyPackage.zip
	
	.EXAMPLE
		# Installs package using specific connection parameters
		.\MyPackage.zip | Install-PowerUpPackage -SqlInstance 'myserver\instance1' -Database 'MyDb' -ExecutionTimeout 3600 
		
	.EXAMPLE
		# Installs package using custom logging parameters and schema tracking table
		.\MyPackage.zip | Install-PowerUpPackage -SchemaVersionTable dbo.SchemaHistory -OutputFile .\out.log -Append

	.EXAMPLE
		# Installs package using custom configuration file
		.\MyPackage.zip | Install-PowerUpPackage -ConfigurationFile .\localconfig.json

	.EXAMPLE
		# Installs package using variables instead of specifying values directly
		.\MyPackage.zip | Install-PowerUpPackage -SqlInstance '#{server}' -Database '#{db}' -Variables @{server = 'myserver\instance1'; db = 'MyDb'}
#>
	
	[CmdletBinding(SupportsShouldProcess = $true)]
	param
	(
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			Position = 1)]
		[Alias('Name', 'Package', 'Filename')]
		[string]$Path,
		[string]$WorkSpace,
		[Parameter(Position = 2)]
		[Alias('Server', 'SqlServer', 'DBServer', 'Instance')]
		[string]$SqlInstance,
		[Parameter(Position = 3)]
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
		[Alias('ArgumentList')]
		[hashtable]$Variables,
		[switch]$Force,
		[switch]$SkipValidation,
		[string]$OutputFile,
		[switch]$Append,
		[Alias('Config')]
		[string]$ConfigurationFile,
		[hashtable]$Configuration
	)
	
	begin {
	}
	process {
		if (!(Test-Path $Path)) {
			throw "Package $Path not found. Aborting deployment."
			return
		}
		else {
			$pFile = Get-Item $Path
		}
		
		#Create workspace folder
		if (!$Workspace) {
			$noWorkspace = $true
			if ($PSCmdlet.ShouldProcess("Creating temporary folder")) {
				$workFolder = New-TempWorkspaceFolder
			}
			else {
				$workFolder = "NonexistingPath"
			}
		}
		elseif (!(Test-Path $WorkSpace -PathType Container)) {
			if ($PSCmdlet.ShouldProcess("Creating workspace folder $WorkSpace")) {
				$workFolder = New-Item -Path $WorkSpace -ItemType Directory -ErrorAction Stop
			}
			else {
				$workFolder = "NonexistingPath123456743452345"
			}
		}
		else {
			$workFolder = Get-Item -Path $WorkSpace
		}

		#Ensure that temporary workspace is removed
		try {
			#Extract package
			if ($PSCmdlet.ShouldProcess($pFile, "Extracting package to $workFolder")) {
				Expand-Archive -Path $pFile -DestinationPath $workFolder -Force:$Force
			}
		
			#Validate package
			if (!$SkipValidation) {
				if ($PSCmdlet.ShouldProcess($pFile, "Validating package in $workFolder")) {
					$validation = Test-PowerUpPackage -Path $workFolder -Unpacked
					if ($validation.IsValid -eq $false) {
						$throwMessage = "The following package items have failed validation: "
						$throwMessage += ($validation.ValidationTests | Where-Object { $_.Result -eq $false }).Item -join ", "
						throw $throwMessage
					}
				}
			}

			#Reading the package
			$packageFileName = Join-Path $workFolder ([PowerUpConfig]::GetPackageFileName())
			if ($PSCmdlet.ShouldProcess($packageFileName, "Reading package file")) {
				$package = [PowerUpPackage]::FromFile($packageFileName)
			}

			#Overwrite config file if specified
			if ($ConfigurationFile) {
				Update-PowerUpConfig -Path $workFolder -ConfigurationFile $ConfigurationFile -Variables $Variables -Unpacked
			}
			if ($Configuration) {
				Update-PowerUpConfig -Path $workFolder -Configuration $Configuration -Variables $Variables -Unpacked
			} 
		
			#Start deployment
			$params = @{ PackageFile = $packageFileName }
			foreach ($key in ($PSBoundParameters.Keys | Where-Object {
						$_ -in @(
							'SqlInstance',
							'Database',
							'DeploymentMethod',
							'ConnectionTimeout',
							'ExecutionTimeout',						
							'Encrypt',
							'Credential',
							'UserName',
							'Password',
							'SchemaVersionTable',
							'Silent',
							'OutputFile',
							'Variables',
							'Append'
						)
					})) {
				$params += @{ $key = $PSBoundParameters[$key] }
			}
			Write-Verbose "Preparing to start the deployment with custom parameters: $($params.Keys -join ', ')"
			if ($PSCmdlet.ShouldProcess($params.PackageFile, "Initiating the deployment of the package")) {
				Invoke-PowerUpDeployment @params
			}
		}
		catch {
			throw $_
		}
		finally {
			if ($noWorkspace) {
				if ($workFolder.Name -like 'PowerUpWorkspace*') {
					if ($PSCmdlet.ShouldProcess($workFolder, "Removing temporary folder")) {
						Remove-Item $workFolder -Recurse -Force
					}
				}
			}
		}
	}
	end {
		
	}
}
