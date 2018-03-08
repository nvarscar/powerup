Function Get-PowerUpModuleFileList {
	<#
.SYNOPSIS
Returns all module files based on json file in the module root

.DESCRIPTION
Returns objects from PowerUp.json. Is used internally to load files into the package.

.EXAMPLE
# Returns module files
Get-PowerUpModuleFileList
#>	
	Param ()
	Function ModuleFile {
		Param (
			$Path,
			$Type
		)
		$obj = @{} | Select-Object Path, Name, FullName, Type, Directory
		$obj.Path = $Path
		$obj.Directory = Split-Path $Path -Parent
		$obj.Type = $Type
		$file = Get-Item -Path (Join-Path "$PSScriptRoot\.." $Path)
		$obj.FullName = $file.FullName
		$obj.Name = $file.Name
		$obj
	}

	$moduleCatalog = Get-Content (Join-Path "$PSScriptRoot\.." "PowerUp.json") -Raw | ConvertFrom-Json
	foreach ($property in $moduleCatalog.psobject.properties.Name) {
		foreach ($file in $moduleCatalog.$property) {
			ModuleFile $file $property
		}
	}
}
