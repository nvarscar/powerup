function Test-PowerUpPackage {
<#
	.SYNOPSIS
		Deploys a prepared PowerUp package
	
	.DESCRIPTION
		A detailed description of the Install-PowerUpPackage function.
	
	.PARAMETER Path
		A description of the Path parameter.
	
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
	
	.PARAMETER LogToTable
		A description of the LogToTable parameter.
	
	.PARAMETER Silent
		A description of the Silent parameter.
	
	.PARAMETER Variables
		A description of the Variables parameter.
	
	.EXAMPLE
		PS C:\> Install-PowerUpPackage
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[Alias('Name', 'Package')]
		[string]$Path,
		[switch]$Unpacked
	)
	begin {
		function Return-ValidationItem ([string]$name, [bool]$result) {
			$object = @{ } | Select-Object Name, Result
			$object.Name = $name
			$object.Result = $result
			$object
		}
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
		
	}
	process {
		if (!$Unpacked) {
			#Extract package
			Write-Verbose "Extracting package $Path to $workFolder"
			Expand-Archive -Path $Path -DestinationPath $workFolder
		}
		
		Write-Verbose "Starting validation"
		$validationResults = @()
		
		$validationResults += Return-ValidationItem 'PackageFile' (Test-Path "$workFolder\PowerUp.package.json")
		
		$package = [PowerUpPackage]::FromFile("$workFolder\PowerUp.package.json")
		$validationResults += Return-ValidationItem 'DeploymentScript' (Test-Path "$workFolder\$($package.DeployScript)")
		$validationResults += Return-ValidationItem 'ConfigurationFile' (Test-Path "$workFolder\$($package.ConfigurationFile)")
		
		foreach ($build in $package.builds) {
			$contentPath = "$workFolder\$($package.ScriptDirectory)"
			$validationResults += Return-ValidationItem $build (Test-Path "$contentPath\$($build.build)" -PathType Container)
			foreach ($script in $build.scripts) {
				$validationResults += Return-ValidationItem $script ((Test-Path "$contentPath\$($script.packagePath)" -PathType Leaf) -and ((Get-FileHash "$contentPath\$($script.packagePath)").Hash -eq $script.hash))
			}
		}
		$outObject = @{ } | Select-Object Package, IsValid, ValidationTests
		$outObject.Package = $Path
		$outObject.IsValid = $validationResults.Result | ForEach-Object -Begin { $r = $true } -Process { $r = $r -and $_ } -End { $r }
		$outObject.ValidationTests = $validationResults
		$outObject
	}
	end {
		if (!$Unpacked) {
			if ($workFolder.Name -like 'PowerUpWorkspace*') {
				Write-Verbose "Removing temporary folder $workFolder"
				Remove-Item $workFolder -Recurse -Force
			}
		}
		
	}
}
