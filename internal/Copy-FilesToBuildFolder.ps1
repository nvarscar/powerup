function Copy-FilesToBuildFolder {
	<#
	Copies all the files from the build to the destination folder inside the package script directory ([content]).
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param
	(
		[Parameter(Mandatory = $true)]
		[PowerUpBuild]$Build,
		[Parameter(Mandatory = $true)]
		[string]$ScriptPath
	)
	
	if ($pscmdlet.ShouldProcess($Build, "Creating $Build folder")) {
		$buildFolder = Join-Path $ScriptPath $Build.build
		if (-not (Test-Path $buildFolder)) {
			Write-Verbose "Creating folder $buildFolder"
			$null = New-Item -Path $buildFolder -ItemType Directory
		}
	}

	if ($pscmdlet.ShouldProcess($Build, "Copying $Build scripts")) {
		foreach ($script in $Build.scripts) {
			$destination = Join-Path $ScriptPath $script.packagePath
			$destFolder = Split-Path $destination -Parent
			if (-not (Test-Path $destFolder)) {
				Write-Verbose "Creating folder $destFolder"
				$null = New-Item -Path $destFolder -ItemType Directory
			}
			Write-Verbose "Copying file $($script.sourcePath) to $destination"
			Copy-Item -Path $script.sourcePath -Destination $destination
		}
	}
}