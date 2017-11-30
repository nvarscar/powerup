
function New-TempWorkspaceFolder {
<#
	.SYNOPSIS
		Creates a temporary folder for the runtime operations
	
	.DESCRIPTION
		A detailed description of the New-TempWorkspaceFolder function.
	
	.EXAMPLE
				PS C:\> New-TempWorkspaceFolder
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()]
	param ()
	$currentDate = Get-Date
	$tempFolder = "PowerUpWorkspace_" + [string]$currentDate.Year + [string]$currentDate.Month + [string]$currentDate.Day + [string]$currentDate.Hour + [string]$currentDate.Minute + [string]$currentDate.Second + '_' + [string](Get-Random(99999))
	$tempPath = [System.IO.Path]::GetTempPath()
	$tempPath = Join-Path $tempPath $tempFolder
	$workFolder = New-Item $tempPath -ItemType Directory
	return $workFolder
}
