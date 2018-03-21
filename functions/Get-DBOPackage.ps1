Function Get-DBOPackage {
	<#
	.SYNOPSIS
	Shows information about the existin DBOps package
	
	.DESCRIPTION
	Reads DBOps package header and configuration files and returns an object with corresponding properties.
	
	.PARAMETER Path
	Path to the DBOps package

	Aliases: Name, FileName, Package

	.PARAMETER Unpacked
	Mostly intended for internal use. Gets package information from extracted package.

	.PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

	.EXAMPLE
	# Returns information about the package myPackage.zip, only including infomartion about builds 1.1 and 1.2
	Get-DBOPackage -Path c:\temp\myPackage.zip -Build 1.1, 1.2
	
	.NOTES
	
	#>
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $false,
			ValueFromPipeline = $true)]
		[Alias('FileName', 'Name', 'Package')]
		[string[]]$Path,
		[switch]$Unpacked
	)
	begin {

	}
	process {
		if ($Path) {
			foreach ($pathItem in (Get-Item $Path)) {
				if ($Unpacked) {
					if ($pathItem.PSIsContainer) {
						$packageFileName = [DBOpsConfig]::GetPackageFileName()
						$packageFile = Join-Path $pathItem.FullName $packageFileName
						Write-Verbose "Loading package $packageFileName from folder $($pathItem.FullName)"
						[DBOpsPackageFile]::new($packageFile)
					}
					else {
						Write-Verbose "Loading package from the json file $pathItem"
						[DBOpsPackageFile]::new($pathItem.FullName)
					}
				}
				else {
					Write-Verbose "Loading package file from the archive $pathItem"
					[DBOpsPackage]::new($pathItem.FullName)
				}
			}
		}
		else {
			Write-Verbose "Creating new DBOps package $pFile"
			[DBOpsPackage]::new()
		}
	}
	end {

	}
}