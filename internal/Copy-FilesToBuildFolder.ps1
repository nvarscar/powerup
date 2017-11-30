function Copy-FilesToBuildFolder {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param
	(
		[Parameter(Mandatory = $true)]
		[PowerUpBuild]$Build,
		[Parameter(Mandatory = $true)]
		[string]$ScriptPath
	)
	
<#
	Copies all the files from the build to the destination folder inside the package script directory ([content]).
#>
	if ($pscmdlet.ShouldProcess($Build, "Processing $Build")) {
		foreach ($script in $Build.scripts) {
			$destination = Join-Path $ScriptPath $script.packagePath
			$destFolder = Split-Path $destination -Parent
			if (-not (Test-Path $destFolder)) {
				Write-Verbose "Creating folder $destFolder"
				$null = New-Item -Path $destFolder -ItemType Directory
			}
			Write-Verbose "Copying file $($script.sourcePath)"
			Copy-Item -Path $script.sourcePath -Destination $destination
		}
	}
}