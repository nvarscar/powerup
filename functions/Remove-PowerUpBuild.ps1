Function Remove-PowerUpBuild {
	<#
	.SYNOPSIS
	Removes one or more builds from the PowerUp package
	
	.DESCRIPTION
	Remove specific list of builds from the existing PowerUp package keeping all other parts of the package intact
	
	.PARAMETER Path
	Path to the PowerUp package
	
	.PARAMETER Build
	One or more builds to remove from the package.
	
	.PARAMETER SkipValidation
	Skip package validation step when attempting to remove build(s) from the package.
	
	.EXAMPLE
	# Removes builds 1.1 and 1.2 from the package
	Remove-PowerUpBuild -Path c:\temp\myPackage.zip -Build 1.1, 1.2

	.EXAMPLE
	# Removes all 1.* builds from the package
	$builds = (Get-PowerUpPackage c:\temp\myPackage.zip).Builds
	$builds.Build | Where { $_ -like '1.*' } | Remove-PowerUpBuild -Path c:\temp\myPackage.zip
	
	.NOTES
	
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param(
		[Parameter(Mandatory = $true,
			Position = 1)]
		[Alias('FileName', 'Name', 'Package')]
		[string]$Path,
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			Position = 2)]
		[string[]]$Build,
		[switch]$SkipValidation
	)
	begin {
		if (!(Test-Path $Path)) {
			throw "Package $Path not found. Aborting build."
			return
		}
		else {
			$pFile = Get-Item $Path
		}
		$buildCollection = @()
	}
	process {
		foreach ($currentBuild in $Build) {
			$buildCollection += $currentBuild
		}
	}
	end {
		$workFolder = New-TempWorkspaceFolder
		try {
			#Extract package
			Write-Verbose "Extracting archive $pFile to $workFolder"
			Expand-Archive -Path $pFile -DestinationPath $workFolder

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
			
			foreach ($currentBuild in $buildCollection) {

				#Verify that build exists
				if ($currentBuild -notin $package.EnumBuilds()) {
					Write-Warning "Build $currentBuild not found in the package, skipping."
					continue
				}
				
				#Get build object
				$buildObject = $package.GetBuild($currentBuild)

				$currentBuildPath = Join-Path (Join-Path $workFolder $package.ScriptDirectory) $buildObject.build

				#Remove build from the object
				Write-Verbose "Removing $currentBuild from the package object"
				$package.RemoveBuild($currentBuild)
				
				$packagePath = Join-Path $workFolder $package.PackageFile
				Write-Verbose "Writing package file $packagePath"
				$package.SaveToFile($packagePath, $true)
				
				#Remove build folder
				If (Test-Path $currentBuildPath) {
					Remove-Item $currentBuildPath -Recurse -Force
				}
				else {
					Write-Warning -Message "Build folder $currentBuildPath was not found in the package"
				}
			}

			if ($pscmdlet.ShouldProcess($pFile, "Saving changes to the package")) {
				#Re-compress archive
				Write-Verbose "Repackaging original package $pFile"
				Compress-Archive "$workFolder\*" -DestinationPath $pFile -Force
			}
		}
		catch {
			throw $_
		}
		finally {
			if ($workFolder.Name -like 'PowerUpWorkspace*') {
				Remove-Item $workFolder -Recurse -Force
			}
		}
	}
}