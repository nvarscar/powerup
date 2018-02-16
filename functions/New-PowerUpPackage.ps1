<#
	.SYNOPSIS
		Creates a new deployment package from specified set of scripts
	
	.DESCRIPTION
		Creates a new zip package which would contain a set of deployment scripts
	
	.PARAMETER ScriptPath
		A description of the ScriptPath parameter.
	
	.PARAMETER Name
		Output package name. Can be full file path or just a file name.
	
	.PARAMETER Build
		A description of the Build parameter.
	
	.PARAMETER ApplicationName
		A description of the ApplicationName parameter.
	
	.PARAMETER DeploymentMethod
		A description of the DeploymentMethod parameter.
	
	.PARAMETER UserName
		A description of the UserName parameter.
	
	.PARAMETER Password
		A description of the Password parameter.
	
	.PARAMETER ConnectionTimeout
		A description of the ConnectionTimeout parameter.

	.PARAMETER ExecutionTimeout
		A description of the ExecutionTimeout parameter.
	
	.PARAMETER Encrypt
		A description of the Encrypt parameter.
	
	.PARAMETER Force
		A description of the Force parameter.
	
	.PARAMETER ConfigurationFile
		A description of the ConfigurationFile parameter.
	
	.PARAMETER Version
		A description of the Version parameter.
	
	.EXAMPLE
		PS C:\> New-PowerUpPackage -ScriptPath $value1 -Name 'Value2'
	
	.NOTES
		Additional information about the function.
#>
function New-PowerUpPackage {
	[CmdletBinding(DefaultParameterSetName = 'Default',
		SupportsShouldProcess = $true)]
	param
	(
		[Parameter(Mandatory = $false,
			Position = 1)]
		[Alias('FileName', 'Path', 'Package')]
		[string]$Name = (Split-Path (Get-Location) -Leaf),
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			Position = 2)]
		[object[]]$ScriptPath,
		[string]$Build,
		[Parameter(ParameterSetName = 'Default')]
		[string]$ApplicationName = 'PowerUp',
		[Parameter(ParameterSetName = 'Default')]
		[ValidateSet('SingleTransaction', 'TransactionPerScript', 'NoTransaction')]
		[string]$DeploymentMethod = 'NoTransaction',
		[Parameter(ParameterSetName = 'Default')]
		[string]$UserName,
		[Parameter(ParameterSetName = 'Default')]
		[securestring]$Password,
		[Parameter(ParameterSetName = 'Default')]
		[int]$ConnectionTimeout,
		[Parameter(ParameterSetName = 'Default')]
		[int]$ExecutionTimeout,
		[Parameter(ParameterSetName = 'Default')]
		[switch]$Encrypt,
		[switch]$Force,
		[Parameter(ParameterSetName = 'Config')]
		[Alias('Config')]
		[string]$ConfigurationFile
	)
	
	begin {
		#Set package extension
		if ($Name.EndsWith('.zip') -eq $false) {
			$Name = "$Name.zip"
		}
		
		#Check configuration parameter if specified
		if ($ConfigurationFile -and (Test-Path $ConfigurationFile) -eq $false) {
			throw 'Configuration file does not exist'
			return
		}
		#Generate a config object
		Write-Verbose "Loading config $ConfigurationFile"
		$config = Get-PowerUpConfig $ConfigurationFile
		
		#Apply overrides if any
		foreach ($key in ($PSBoundParameters.Keys | Where-Object { $_ -ne 'Variables' })) {
			if ($key -in $config.psobject.Properties.Name) {
				Write-Verbose "Overriding config property $key"
				$config.$key = $PSBoundParameters[$key]
			}
		}
		
		#Create a package object
		$package = [PowerUpPackage]::new()
		
		#Create new build
		if ($Build) {
			$buildNumber = $Build
		}
		else {
			$buildNumber = Get-NewBuildNumber
		}
	}
	process {
		foreach ($scriptItem in $ScriptPath) {
			if (!(Test-Path $scriptItem)) {
				throw "The following path is not valid: $scriptItem"
			}
		}
	}
	end {
		if ($pscmdlet.ShouldProcess($package, "Generate a package file")) {
			#Create temp folder
			$workFolder = New-TempWorkspaceFolder

			#Ensure that temporary workspace is removed
			try {			
				#Copy package contents to the temp folder
				Write-Verbose "Copying deployment file $($package.DeploySource)"
				Copy-Item -Path $package.DeploySource -Destination (Join-Path $workFolder $package.DeployScript)
				if ($package.PreDeploySource) {
					Write-Verbose "Copying pre-deployment file $($package.PreDeploySource)"
					Copy-Item -Path $package.PreDeploySource -Destination (Join-Path $workFolder $package.PreDeployScript)
				}
				if ($package.PostDeploySource) {
					Write-Verbose "Copying post-deployment file $($package.PostDeploySource)"
					Copy-Item -Path $package.PostDeploySource -Destination (Join-Path $workFolder $package.PostDeployScript)
				}

				#Write files into the folder
				$configPath = Join-Path $workFolder $package.ConfigurationFile
				Write-Verbose "Writing configuration file $configPath"
				$config | ConvertTo-Json -Depth 2 | Out-File $configPath
			
				$packagePath = Join-Path $workFolder $package.PackageFile
				Write-Verbose "Writing package file $packagePath"
				$package.SaveToFile($packagePath)

				#Copy module into the archive
				Copy-ModuleFiles -Path (Join-Path $workFolder "Modules\PowerUp")

				#Create a new build
				$null = Add-PowerUpBuild -Path $workFolder -Build $buildNumber -ScriptPath $ScriptPath -Unpacked -SkipValidation

				#Compress the files
				Write-Verbose "Creating archive file $Name"
				Compress-Archive "$workFolder\*" -DestinationPath $Name -Force:$Force
			
				Get-Item $Name
			}
			catch {
				throw $_
			}
			finally {
				if ($workFolder.Name -like 'PowerUpWorkspace*') {
					Write-Verbose "Removing temporary folder $workFolder"
					Remove-Item $workFolder -Recurse -Force
				}
			}
		}
		
	}
}
