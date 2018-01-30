
function Add-PowerUpBuild {
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
	[CmdletBinding(DefaultParameterSetName = 'Default',
		SupportsShouldProcess = $true)]
	param
	(
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			Position = 1)]
		[object[]]$ScriptPath,
		[Parameter(Mandatory = $false,
			Position = 2)]
		[Alias('FileName', 'Name', 'Package')]
		[string]$Path,
		[Parameter(ParameterSetName = 'Default')]
		[string]$Build,
		[switch]$SkipValidation,
		[switch]$NewOnly,
		[switch]$UniqueOnly
	)
	
	begin {
		$currentDate = Get-Date
		if (!$Build) {
			$Build = Get-NewBuildNumber
		}
		if (!(Test-Path $Path)) {
			throw "Package $Path not found. Aborting deployment."
			return
		}
		else {
			$pFile = Get-Item $Path
		}
		
		$scriptCollection = @()
	}
	process {
		foreach ($scriptItem in $ScriptPath) {
			if (!(Test-Path $scriptItem)) {
				throw "The following path is not valid: $ScriptPath"
			}
			Write-Verbose "Processing path $scriptItem"
			$scriptCollection += Get-ChildScriptItem $scriptItem
		}
	}
	end {
		#Create a temp folder
		$workFolder = New-TempWorkspaceFolder
		
		#Ensure that temp workspace is always cleaned up
		try {
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
			
			#Load package object
			Write-Verbose "Loading package information from $pFile"
			$package = [PowerUpPackage]::FromFile((Join-Path $workFolder "PowerUp.package.json"))
			
			$scriptsToAdd = @()
			foreach ($childScript in $scriptCollection) { 
				if ($NewOnly) {
					#Check if the script path was already added in one of the previous builds
					if ($package.SourcePathExists($childScript.FullName)) {
						Write-Verbose "File $($childScript.FullName) was found among the package source files, skipping."
						continue
					}
				}
				if ($UniqueOnly) {
					#Check if the script hash was already added in one of the previous builds
					if ($package.ScriptExists($childScript.FullName)) {
						Write-Verbose "Hash of the file $($childScript.FullName) was found among the package scripts, skipping."
						continue
					}
				}
				$scriptsToAdd += $childScript
			}	


			if (!$scriptsToAdd) {
				throw "No scripts have been selected, aborting command."
			}

			#Create new build object
			$currentBuild = [PowerUpBuild]::new($Build)

			foreach ($buildScript in $scriptsToAdd) {
				Write-Verbose "Adding file '$($buildScript.FullName)' to $currentBuild"
				$currentBuild.NewScript($buildScript.FullName, $buildScript.ReplacePath) 
			}

			Write-Verbose "Adding $currentBuild to the package object"
			$package.AddBuild($currentBuild)
		
			if ($pscmdlet.ShouldProcess($package, "Adding files to the package")) {
				$scriptDir = Join-Path $workFolder $package.ScriptDirectory
				if (!(Test-Path $scriptDir)) {
					$null = New-Item $scriptDir -ItemType Directory
				}
				Copy-FilesToBuildFolder $currentBuild $scriptDir
				
				$packagePath = Join-Path $workFolder $package.PackageFile
				Write-Verbose "Writing package file $packagePath"
				$package.SaveToFile($packagePath, $true)
				
				Write-Verbose "Repackaging original package $Path"
				Compress-Archive "$workFolder\*" -DestinationPath $Path -Force
				
				Get-Item $Path
				
			}
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