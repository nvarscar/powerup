function Test-PowerUpPackage {
	<#
	.SYNOPSIS
		Performs structural and integrity checks agains existing PowerUp package
	
	.DESCRIPTION
		Runs a number of tests agains PowerUp package contents and returns detailed report 
	
	.PARAMETER Path
		Path to the existing PowerUpPackage.
		Aliases: Name, FileName, Package
	
	.PARAMETER Unpacked
		Mostly intended for internal use. Performs tests against already extracted package.

	.PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
		#Validates package and returns validation details
		Test-PowerUpPackage .\Mypkg.zip

	.EXAMPLE
		#Validates package and returns boolean value
		(Test-PowerUpPackage .\Mypkg.zip).IsValid
	
#>
	
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[Alias('Name', 'FileName', 'Package')]
		[string]$Path,
		[switch]$Unpacked
	)
	begin {
		function Select-ValidationItem ([string]$name, [bool]$result) {
			$object = @{ } | Select-Object Name, Result
			$object.Name = $name
			$object.Result = $result
			$object
		}		
	}
	process {
		if (!(Test-Path $Path)) {
			throw "Path not found: $Path"
			return
		}
		if ($Unpacked) {
			if ((Split-Path $Path -Leaf) -eq "PowerUp.package.json" -and (Test-Path $Path -PathType Leaf)) {
				$workFolder = Get-Item (Split-Path $Path -Parent)
			}
			elseif (Test-Path $Path -PathType Container) {
				$workFolder = Get-Item $Path
			}
			else {
				throw "Path is not a container: $Path"
				return
			}
		}
		else {
			$workFolder = New-TempWorkspaceFolder
		}
		
		#Ensure that temporary workspace is removed
		try {					
			if (!$Unpacked) {
				#Extract package
				Write-Verbose "Extracting package $Path to $workFolder"
				Expand-Archive -Path $Path -DestinationPath $workFolder
			}

			$moduleManifest = "$workFolder\Modules\PowerUp\PowerUp.psd1"
			Write-Verbose "Starting validation"
			$validationResults = @()
		
			$validationResults += Select-ValidationItem 'PackageFile' (Test-Path "$workFolder\PowerUp.package.json")
		
			$package = [PowerUpPackage]::FromFile("$workFolder\PowerUp.package.json")
			$validationResults += Select-ValidationItem 'DeploymentScript' (Test-Path "$workFolder\$($package.DeployScript)")
			$validationResults += Select-ValidationItem 'ConfigurationFile' (Test-Path "$workFolder\$($package.ConfigurationFile)")
			$validationResults += Select-ValidationItem 'ModuleManifest' (Test-Path $moduleManifest)
		
			foreach ($build in $package.builds) {
				$contentPath = "$workFolder\$($package.ScriptDirectory)"
				$validationResults += Select-ValidationItem $build (Test-Path "$contentPath\$($build.build)" -PathType Container)
				foreach ($script in $build.scripts) {
					$validationResults += Select-ValidationItem $script ((Test-Path "$contentPath\$($script.packagePath)" -PathType Leaf) -and ((Get-FileHash "$contentPath\$($script.packagePath)").Hash -eq $script.hash))
				}
			}
			
			
			$outObject = @{ } | Select-Object Package, ModuleVersion, PackageVersion, IsValid, ValidationTests
			if ($validationResults | Where-Object Name -eq 'ModuleManifest' | Select-Object -ExpandProperty Result) {
				$outObject.ModuleVersion = (Test-ModuleManifest -Path $moduleManifest).Version
			}
			$outObject.Package = $Path
			$outObject.PackageVersion = $package.GetVersion()
			$outObject.IsValid = $validationResults.Result -notcontains $false
			$outObject.ValidationTests = $validationResults
			$outObject
		}
		catch {
			throw $_
		}
		finally {
			#Cleanup
			if (!$Unpacked) {
				if ($workFolder.Name -like 'PowerUpWorkspace*') {
					Write-Verbose "Removing temporary folder $workFolder"
					Remove-Item $workFolder -Recurse -Force
				}
			}
		}
	}
	end {
	
	}
}
