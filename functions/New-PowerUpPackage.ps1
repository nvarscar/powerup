<#
	.SYNOPSIS
		Creates a new deployment package from a specified set of scripts
	
	.DESCRIPTION
		Creates a new zip package which would contain a set of deployment scripts.
		Deploy.ps1 inside the package will initiate the deployment of the extracted package.
		Can be created with predefined parameters, which would allow for deployments without specifying additional info.
	
	.PARAMETER ScriptPath
		A collection of script files to add to the build. Accepts Get-Item/Get-ChildItem objects and wildcards.
		Will recursively add all of the subfolders inside folders. See examples if you want only custom files to be added.
		During deployment, scripts will be following this deployment order:
		 - Item order provided in the ScriptPath parameter
		   - Files inside each child folder (both folders and files in alphabetical order)
			 - Files inside the root folder (in alphabetical order)
			 
		Aliases: SourcePath
	
	.PARAMETER Path
		Package file name. Will add '.zip' extention, if no extension is specified

		Aliases: Name, FileName, Package
	
	.PARAMETER Build
		A string that would be representing a build number of the first build in this package. 
		A single package can span multiple builds - see Add-PowerUpBuild.
		Optional - can be genarated automatically.
		Can only contain characters that will be valid on the filesystem.
	
	.PARAMETER Force
		Replaces the target file specified in -Path if it already exists.
	
	.PARAMETER ConfigurationFile
		A path to the custom configuration json file
	
	.PARAMETER Configuration
		Hashtable containing necessary configuration items. Will override parameters in ConfigurationFile

	.PARAMETER Variables
		Hashtable with variables that can be used inside the scripts and deployment parameters.
		Proper format of the variable tokens is #{MyVariableName}
		Can also be provided as a part of Configuration hashtable: -Configuration @{ Variables = @{ Var1 = ...; Var2 = ...}}
	
	.EXAMPLE
		PS C:\> New-PowerUpPackage -ScriptPath $value1 -Name 'Value2'
	
	.NOTES
		Additional information about the function.
#>
function New-PowerUpPackage {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param
	(
		[Parameter(Mandatory = $false,
			Position = 1)]
		[Alias('FileName', 'Name', 'Package')]
		[string]$Path = (Split-Path (Get-Location) -Leaf),
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			Position = 2)]
		[Alias('SourcePath')]
		[object[]]$ScriptPath,
		[string]$Build,
		[switch]$Force,
		[Alias('Config')]
		[hashtable]$Configuration,
		[Alias('ConfigFile')]
		[string]$ConfigurationFile,
		[hashtable]$Variables
	)
	
	begin {
		#Set package extension if there is none
		if ($Path.IndexOf('.') -eq -1) {
			$Path = "$Path.zip"
		}
		
		#Combine Variables and Configuration into a single object
		$configTable = $Configuration
		if ($Variables) { $configTable += @{ Variables = $Variables } }
		
		#Get configuration object according to current config options
		$config = Get-PowerUpConfig -Path $ConfigurationFile -Configuration $configTable
	
		#Create a package object
		$package = [PowerUpPackage]::new()
		
		#Create new build
		if ($Build) {
			$buildNumber = $Build
		}
		else {
			$buildNumber = Get-NewBuildNumber
		}
		
		$scriptCollection = @()
	}
	process {
		$scriptCollection += $ScriptPath
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
				$config.SaveToFile($configPath)
			
				$packagePath = Join-Path $workFolder $package.PackageFile
				Write-Verbose "Writing package file $packagePath"
				$package.SaveToFile($packagePath)

				#Copy module into the archive
				Copy-ModuleFiles -Path (Join-Path $workFolder "Modules\PowerUp")

				#Create a new build
				$null = Add-PowerUpBuild -Path $workFolder -Build $buildNumber -ScriptPath $scriptCollection -Unpacked -SkipValidation

				#Storing package details in a variable
				$packageInfo = Get-PowerUpPackage -Path $workFolder -Unpacked

				#Compress the files
				Write-Verbose "Creating archive file $Path"
				Compress-Archive "$workFolder\*" -DestinationPath $Path -Force:$Force
			
				#Preparing output object
				$outputObject = [PowerUpPackageFile]::new((Get-Item $Path))
				$outputObject.Config = $packageInfo.Config
				$outputObject.Version = $packageInfo.Version
				$outputObject.ModuleVersion = $packageInfo.ModuleVersion
				$outputObject.Builds = $packageInfo.Builds	
				$outputObject
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
