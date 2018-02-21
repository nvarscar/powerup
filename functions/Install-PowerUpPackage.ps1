function Install-PowerUpPackage {
	<#
	.SYNOPSIS
		Deploys a prepared PowerUp package
	
	.DESCRIPTION
		A detailed description of the Install-PowerUpPackage function.
	
	.PARAMETER Path
		A description of the Path parameter.
	
	.PARAMETER WorkSpace
		A description of the WorkSpace parameter.
	
	.PARAMETER SqlInstance
		A description of the SqlInstance parameter.
	
	.PARAMETER Database
		A description of the Database parameter.
	
	.PARAMETER DeploymentMethod
		A description of the DeploymentMethod parameter.
	
	.PARAMETER ConnectionTimeout
		A description of the ConnectionTimeout parameter.
		
	.PARAMETER ExecutionTimeout
		A description of the ExecutionTimeout parameter.
	
	.PARAMETER Encrypt
		A description of the Encrypt parameter.
	
	.PARAMETER Credential
		A description of the Credential parameter.
	
	.PARAMETER UserName
		A description of the UserName parameter.
	
	.PARAMETER Password
		A description of the Password parameter.
	
	.PARAMETER SchemaVersionTable
		A description of the SchemaVersionTable parameter.
	
	.PARAMETER Silent
		A description of the Silent parameter.
	
	.PARAMETER Variables
		A description of the Variables parameter.
	
	.PARAMETER Force
		A description of the Force parameter.
	
	.PARAMETER SkipValidation
		A description of the SkipValidation parameter.
	
	.PARAMETER OutputFile
		A description of the OutputFile parameter.
	
	.PARAMETER Append
		A description of the Append parameter.
	
	.EXAMPLE
		PS C:\> Install-PowerUpPackage
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding(SupportsShouldProcess = $true)]
	param
	(
		[Parameter(Mandatory = $true,
			Position = 1)]
		[Alias('Name', 'Package', 'Filename')]
		[string]$Path,
		[string]$WorkSpace,
		[Parameter(Position = 2)]
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
