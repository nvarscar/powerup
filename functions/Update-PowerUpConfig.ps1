function Update-PowerUpConfig {
	<#
	.SYNOPSIS
	Updates configuration file inside the existing PowerUp package
	
	.DESCRIPTION
	Overwrites configuration file inside the existing PowerUp package with the new values provided by user
	
	.EXAMPLE
	Update-PowerUpConfig File.zip -Config ApplicationName -Value 'MyApp'

	.EXAMPLE
	Update-PowerUpConfig File.zip -Values @{'ApplicationName' = 'MyApp'; 'Database' = 'MyDB'}

	.EXAMPLE
	Update-PowerUpConfig File.zip -ConfigurationFile 'myconfig.json'
	
	.NOTES
	
	#>
	[CmdletBinding(DefaultParameterSetName = 'Value',
		SupportsShouldProcess = $true)]
	Param (
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			Position = 1)]
		[Alias('FileName', 'Name', 'Package')]
		[string[]]$Path,
		[Parameter(ParameterSetName = 'Value',
			Mandatory = $true,
			Position = 2 )]
		[ValidateSet('ApplicationName', 'SqlInstance', 'Database', 'DeploymentMethod',
			'ConnectionTimeout', 'ExecutionTimeout', 'Encrypt', 'Credential', 'Username',
			'Password', 'SchemaVersionTable', 'Silent', 'Variables'
		)]
		[string]$Config,
		[Parameter(ParameterSetName = 'Value',
			Mandatory = $true,
			Position = 3 )]
		[AllowNull()][object]$Value,
		[Parameter(ParameterSetName = 'Hashtable',
			Mandatory = $true,
			Position = 2 )]
		[hashtable]$Values,
		[Parameter(ParameterSetName = 'File',
			Mandatory = $true,
			Position = 2 )]
		[Alias('ConfigFile')]
		[string]$ConfigurationFile,
		[switch]$Unpacked
	)
	begin {

	}
	process {
		foreach ($pFile in (Get-Item $Path)) {
			if ($Unpacked) {
				$workFolder = $pFile
			}
			else {
				$workFolder = New-TempWorkspaceFolder
			}
			try {
				if (!$Unpacked) {
					#Extract package files
					Write-Verbose "Extracting package file from $pFile to $workFolder"
					$packageFile = [PowerUpConfig]::GetPackageFileName()
					Expand-ArchiveItem -Path $pFile -DestinationPath $workFolder -Item $packageFile
				}
			
				Write-Verbose "Reading package file from $workFolder"
				$package = [PowerUpPackage]::FromFile((Join-Path $workFolder $packageFile))
				$configFile = $package.ConfigurationFile

				if (!$Unpacked) {
					Write-Verbose "Extracting config file $configFile from $pFile"
					Expand-ArchiveItem -Path $pFile -DestinationPath $workFolder -Item $configFile
				}

				Write-Verbose "Reading config file $configFile from $workFolder"
				$configTempFile = (Join-Path $workFolder $configFile)
				$configObject = [PowerUpConfig]::FromFile($configTempFile)

				#Assign new values
				Write-Verbose "Assigning new values to the config"

				if ($PSCmdlet.ParameterSetName -eq 'Value') {
					$newConfig = @{ $Config = $Value }
				}
				elseif ($PSCmdlet.ParameterSetName -eq 'Hashtable') {
					$newConfig = $Values
				}
				elseif ($PSCmdlet.ParameterSetName -eq 'File') {
					$newConfig = (Get-PowerUpConfig -Path $ConfigurationFile).AsHashtable()
				}

				Write-Verbose "Processing keys $($newConfig.Keys -join ', ')"
				foreach ($property in $newConfig.Keys) {
					$configObject.SetValue($property,$newConfig.$property)
				}

				Write-Verbose "Saving the config file $configTempFile"
				$configObject.SaveToFile($configTempFile, $true)

				if ($pscmdlet.ShouldProcess($pFile, "Updating package with a new config file")) {
					$null = Add-ArchiveItem -Path $pFile -Item $configTempFile
				}
			}
			catch {
				throw $_
			}
			finally {
				if (!$Unpacked -and $workFolder.Name -like 'PowerUpWorkspace*') {
					Write-Verbose "Removing temporary folder $workFolder"
					Remove-Item $workFolder -Recurse -Force
				}
			}
		}
	}
	end {

	}
}
