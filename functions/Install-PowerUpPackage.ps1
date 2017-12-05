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
	
	[CmdletBinding()]
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
		[switch]$Append
	)
	
	begin {
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
			$workFolder = New-TempWorkspaceFolder
		}
		elseif (!(Test-Path $WorkSpace -PathType Container)) {
			Write-Verbose "Creating workspace folder: $WorkSpace"
			$workFolder = New-Item -Path $WorkSpace -ItemType Directory -ErrorAction Stop
		}
		else {
			$workFolder = Get-Item -Path $WorkSpace
		}
	}
	process {
		#Extract package
		Write-Verbose "Extracting package $pFile to $workFolder"
		Expand-Archive -Path $pFile -DestinationPath $workFolder -Force:$Force
		
		#Validate package
		if (!$SkipValidation) {
			$validation = Test-PowerUpPackage -Path $workFolder -Unpacked
			if ($validation.IsValid -eq $false) {
				$throwMessage = "The following package items have failed validation: "
				$throwMessage += ($validation.ValidationTests | Where-Object { $_.Result -eq $false }).Item -join ", "
				throw $throwMessage
			}
		}
		
		#Start deployment
		$params = @{ PackageFile = "$workFolder\PowerUp.package.json" }
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
		
		Write-Verbose "Initiating the deployment of the package $($params.PackageFile)"
		Invoke-PowerUpDeployment @params
	}
	end {
		if ($noWorkspace) {
			if ($workFolder.Name -like 'PowerUpWorkspace*') {
				Write-Verbose "Removing temporary folder $workFolder"
				Remove-Item $workFolder -Recurse -Force
			}
		}
	}
}
