Function Copy-ModuleFiles {
	<#
	.SYNOPSIS
	Copies files of the current module to the specified folder
	
	.DESCRIPTION
	Takes a module model from the json file and copies all of the files to a destination folder, which would later serve as a deployment module
	
	.EXAMPLE
	Copy-ModuleFiles c:\myfolder
	
	.NOTES
	
	#>
	Param (
		[string]$Path
	)
	if (!(Test-Path $Path)) {
		Write-Verbose "Creating new directory $Path for the module"
		$null = New-Item $Path -ItemType Directory
	}
	elseif (Test-Path $Path -PathType Leaf) {
		throw "The path provided is a file, cannot proceed"
	}
	Write-Verbose "Copying module files into the folder $Path"
	foreach ($file in (Get-PowerUpModuleFileList)) {
		if (-not (Test-Path (Join-Path $Path $file.Directory) -PathType Container)) {
			$null = New-Item (Join-Path $Path $file.Directory) -ItemType Directory
		}
		Copy-Item $file.FullName (Join-Path $Path $file.Path) -Force -Recurse
	}
}