
function Add-PowerUpBuild {
	<#
	.SYNOPSIS
		Creates a new build in existing PowerUp package
	
	.DESCRIPTION
		Creates a new build in existing PowerUp package from specified set of scripts.
	
	.PARAMETER ScriptPath
		A collection of script files to add to the build. Accepts Get-Item/Get-ChildItem objects and wildcards.
		Will recursively add all of the subfolders inside folders. See examples if you want only custom files to be added.
		During deployment, scripts will be following this deployment order:
		 - Item order provided in the ScriptPath parameter
		   - Files inside each child folder (both folders and files in alphabetical order)
			 - Files inside the root folder (in alphabetical order)
			 
		Aliases: SourcePath
	
	.PARAMETER Path
		Path to the existing PowerUpPackage.
		Aliases: Name, FileName, Package
	
	.PARAMETER Build
		A string that would be representing a build number of this particular build. 
		Optional - can be genarated automatically.
		Can only contain characters that will be valid on the filesystem.
	
	.PARAMETER SkipValidation
		Skip package validation step when attempting to add build to the package.
	
	.PARAMETER NewOnly
		Out of all specified script files, only add new files that have not been added to any of the package builds yet. 
		Compares file FullName against all the files from the existing builds to determine eligibility.
		Moving file into different folder will make it a new file.
	
	.PARAMETER UniqueOnly
		Out of all specified script files, only add new/modified files that have not been added to any of the package builds yet. 
		Compares file hash against all the file hashes from the existing builds to determine eligibility.
		Moving file into different folder will NOT make it a new file, as it would still have the same hash value.
	
	.PARAMETER Unpacked
		Intended for internal usage. Allows to work with unpacked package structures (basically, folders).
	
	.PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
		# Add new build 2.0 to the existing package using files from .\Scripts\2.0
		Add-PowerUpBuild -Path MyPackage.zip -ScriptPath .\Scripts\2.0 -Build 2.0

	.EXAMPLE
		# Add new build 2.1 to the existing package using modified files from .\Scripts\2.0
		Get-ChildItem .\Scripts\2.0 | Add-PowerUpBuild -Path MyPackage.zip -Build 2.1 -UniqueOnly

	.EXAMPLE
		# Add new build 3.0 to the existing package checking if there were any new files in the Scripts folder
		Add-PowerUpBuild -Path MyPackage.zip -ScriptPath .\Scripts\* -Build 3.0 -NewOnly

	.NOTES
		See 'Get-Help New-PowerUpPackage' for additional info about packages.
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param
	(
		[Parameter(Mandatory = $true,
			Position = 1)]
		[Alias('FileName', 'Name', 'Package')]
		[string]$Path,
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			Position = 2)]
		[Alias('SourcePath')]
		[object[]]$ScriptPath,
		[string]$Build,
		[switch]$SkipValidation,
		[switch]$NewOnly,
		[switch]$UniqueOnly,
		[Parameter(DontShow)]
		[switch]$Unpacked
	)
	
	begin {
		if (!$Build) {
			$Build = Get-NewBuildNumber
		}
		$scriptCollection = @()
		if ($Path -and (Test-Path $Path)) {
			$pFile = Get-Item $Path
		}
		else {
			throw "Package $Path not found. Aborting build."
			return
		}
	}
	process {
		foreach ($scriptItem in $ScriptPath) {
			Write-Verbose "Processing path item $scriptItem"
			$scriptCollection += Get-ChildScriptItem $scriptItem
		}
	}
	end {
		#Create a temp folder
		if ($Unpacked) {
			$workFolder = $pFile
		}
		else {
			$workFolder = New-TempWorkspaceFolder
		}
		
		#Ensure that temp workspace is always cleaned up
		try {
			if (!$Unpacked) {
				#Extract package
				Write-Verbose "Extracting package $pFile to $workFolder"
				Expand-Archive -Path $pFile -DestinationPath $workFolder
			}

			#Validate package
			if (!$SkipValidation) {
				$validation = Test-PowerUpPackage -Path $workFolder -Unpacked
				if ($validation.IsValid -eq $false) {
					$throwMessage = "The following package items have failed validation: "
					$throwMessage += ($validation.ValidationTests | Where-Object { $_.Result -eq $false }).Item -join ", "
					throw $throwMessage
				}
				$moduleVersion = $validation.ModuleVersion
			}
			
			#Load package object
			Write-Verbose "Loading package information from $pFile"
			$package = [PowerUpPackage]::FromFile((Join-Path $workFolder "PowerUp.package.json"))
			
			$scriptsToAdd = @()
			foreach ($childScript in $scriptCollection) { 
				if ($NewOnly) {
					#Check if the script path was already added in one of the previous builds
					if ($package.SourcePathExists($childScript.SourcePath)) {
						Write-Verbose "File $($childScript.SourcePath) was found among the package source files, skipping."
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


			if ($scriptsToAdd) {

				#Create new build object
				$currentBuild = [PowerUpBuild]::new($Build)

				foreach ($buildScript in $scriptsToAdd) {
					Write-Verbose "Adding file '$($buildScript.FullName)' to $currentBuild"
					$currentBuild.NewScript($buildScript.FullName, $buildScript.Depth) 
				}

				Write-Verbose "Adding $currentBuild to the package object"
				$package.AddBuild($currentBuild)
		
				$scriptDir = Join-Path $workFolder $package.ScriptDirectory
				if (!(Test-Path $scriptDir)) {
					$null = New-Item $scriptDir -ItemType Directory
				}

				if ($pscmdlet.ShouldProcess($pFile, "Copying build files")) {
					Copy-FilesToBuildFolder $currentBuild $scriptDir
				}
			
				$packagePath = Join-Path $workFolder $package.PackageFile
				if ($pscmdlet.ShouldProcess($pFile, "Writing package file $packagePath")) {
					$package.SaveToFile($packagePath, $true)
				}

				if ($moduleVersion -and (Test-ModuleManifest -Path "$workfolder\Modules\PowerUp\PowerUp.psd1").Version.CompareTo($moduleVersion) -lt 0) {
					if ($pscmdlet.ShouldProcess($pFile, "Updating inner module version to $moduleVersion")) {
						Copy-ModuleFiles -Path $workFolder
					}
				}

				#Storing package details in a variable
				$packageInfo = Get-PowerUpPackage -Path $workFolder -Unpacked
				
				if (!$Unpacked) {
					if ($pscmdlet.ShouldProcess($pFile, "Repackaging original package")) {
						Compress-Archive "$workFolder\*" -DestinationPath $pFile -Force
					}
				}

				#Preparing output object
				$outputObject = [PowerUpPackageFile]::new((Get-Item $pFile))
				$outputObject.Config = $packageInfo.Config
				$outputObject.Version = $packageInfo.Version
				$outputObject.ModuleVersion = $packageInfo.ModuleVersion
				$outputObject.Builds = $packageInfo.Builds	

			}
			else {
				Write-Warning "No scripts have been selected, the original file is unchanged."
				$outputObject = Get-PowerUpPackage -Path $pFile
			}

			$outputObject
		}
		catch {
			throw $_
		}
		finally {
			if (!$Unpacked -and $workFolder.Name -like 'PowerUpWorkspace*') {
				Write-Verbose "Removing temporary folder $workFolder"
				Remove-Item $workFolder -Recurse -Force
			}
		}
	}
}