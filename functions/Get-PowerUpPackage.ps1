Function Get-PowerUpPackage {
	<#
	.SYNOPSIS
	Shows information about the package
	
	.DESCRIPTION
	Reads package header and configuration files and returns an object with corresponding properties.
	
	.PARAMETER Path
	PowerUp package path
	
	.PARAMETER Build
	If you only want details about a specific builds inside the package
	
	.EXAMPLE
	Get-PowerUpPackage -Path c:\temp\myPackage.zip -Build 1.1, 1.2
	
	.NOTES
	
	#>
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true)]
		[Alias('FileName', 'Name', 'Package')]
		[string[]]$Path,
		[string[]]$Build,
		[switch]$Unpacked
	)
	begin {

	}
	process {
		foreach ($pFile in (Get-Item $Path)) {
			if (!$Unpacked) {
				#Create temp folder
				$workFolder = New-TempWorkspaceFolder
			}
			else {
				$workFolder = $pFile
			}

			#Create output object and set values for default fields
			$packageInfo = $pFile

			if (!$Unpacked) {
				Add-Member -InputObject $packageInfo -MemberType AliasProperty -Name Size -Value Length
			}
			Add-Member -InputObject $packageInfo -MemberType AliasProperty -Name Path -Value FullName
			


			try {
				if (!$Unpacked) {
					#Extract package file
					Write-Verbose "Extracting package file from the archive $pFile to $workFolder"
					Expand-ArchiveItem -Path $pFile -DestinationPath $workFolder -Item "PowerUp.package.json"
				}

				#Load package object
				Write-Verbose "Loading package information from $pFile"
				$package = [PowerUpPackage]::FromFile((Join-Path $workFolder "PowerUp.package.json"))
				$moduleManifest = 'Modules\PowerUp\PowerUp.psd1'

				if (!$Unpacked) {
					#Extract config and module files
					Write-Verbose "Extracting config file $($package.ConfigurationFile) from the archive $pFile to $workFolder"
					Expand-ArchiveItem -Path $pFile -DestinationPath $workFolder -Item $package.ConfigurationFile

					Write-Verbose "Extracting module manifest from the archive $pFile to $workFolder"
					Expand-ArchiveItem -Path $pFile -DestinationPath $workFolder -Item $moduleManifest
				}

				#Load configuration 
				$configPath = Join-Path $workFolder $package.ConfigurationFile
				if (!$package.ConfigurationFile -or !(Test-Path $configPath)) {
					throw "Configuration file cannot be found. The package is corrupted."
				}
				$config = Get-PowerUpConfig $configPath
				Add-Member -InputObject $packageInfo -MemberType NoteProperty -Name Config -Value $config

				Add-Member -InputObject $packageInfo -MemberType NoteProperty -Name Version -Value $package.GetVersion()
				Add-Member -InputObject $packageInfo -MemberType NoteProperty -Name ModuleVersion -Value (Test-ModuleManifest (Join-Path $workFolder $moduleManifest)).Version
				
				#Generate build and script objects
				$builds = @()
				foreach ($currentBuild in $package.builds) {
					if (!$Build -or ($Build -and $currentBuild.Build -in $Build)) {
						$buildInfo = @{} | Select-Object Build, Scripts, CreatedDate
						$buildInfo.Build = $currentBuild.Build
						$buildInfo.CreatedDate = $currentBuild.CreatedDate
						$buildInfo.Scripts = @()
						foreach ($currentScript in $currentBuild.Scripts) {
							$scriptInfo = @{} | Select-Object Name, SourcePath
							$scriptInfo.SourcePath = $currentScript.SourcePath
							$scriptInfo.Name = $currentScript.PackagePath
							$buildInfo.Scripts += $scriptInfo
						}
						$builds += $buildInfo
					}
				}
				Add-Member -InputObject $packageInfo -MemberType NoteProperty -Name Builds -Value $builds

				$packageInfo
			}
			catch {
				throw $_
			}
			finally {
				if (!$Unpacked -and $workFolder.Name -like 'PowerUpWorkspace*') {
					Remove-Item $workFolder -Recurse -Force
				}
			}
		}
	}
	end {

	}
}