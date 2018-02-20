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
			$packageInfo = [PowerUpPackageFile]::new($pFile)

			try {
				if (!$Unpacked) {
					#Extract package file
					Write-Verbose "Extracting package file from the archive $pFile to $workFolder"
					Expand-ArchiveItem -Path $pFile -DestinationPath $workFolder -Item "PowerUp.package.json"
				}

				#Load package object
				Write-Verbose "Loading package information from $pFile"
				$package = [PowerUpPackage]::FromFile((Join-Path $workFolder "PowerUp.package.json"))
				$modulePath = 'Modules\PowerUp'

				if (!$Unpacked) {
					#Extract config and module files
					Write-Verbose "Extracting config file $($package.ConfigurationFile) from the archive $pFile to $workFolder"
					Expand-ArchiveItem -Path $pFile -DestinationPath $workFolder -Item $package.ConfigurationFile

					Write-Verbose "Extracting module core files from the archive $pFile to $workFolder"
					$coreFiles = @()
					foreach ($moduleFile in (Get-ModuleFileList | Where-Object Type -eq 'Core')) {
						$coreFiles += Join-Path $modulePath $moduleFile.Name
					}
					Expand-ArchiveItem -Path $pFile -DestinationPath $workFolder -Item $coreFiles
				}

				#Load configuration 
				$configPath = Join-Path $workFolder $package.ConfigurationFile
				if (!$package.ConfigurationFile -or !(Test-Path $configPath)) {
					throw "Configuration file cannot be found. The package is corrupted."
				}

				$packageInfo.Config = [PowerUpConfig]::FromFile($configPath)
				$packageInfo.Version = $package.GetVersion()
				$moduleManifest = Join-Path (Join-Path $workFolder $modulePath) 'PowerUp.psd1'
				$packageInfo.ModuleVersion = (Test-ModuleManifest $moduleManifest).Version

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
				$packageInfo.Builds = $builds

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