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
		[string]$ConfigName,
		[Parameter(ParameterSetName = 'Value',
			Mandatory = $true,
			Position = 3 )]
		[AllowNull()][object]$Value,
		[Parameter(ParameterSetName = 'Hashtable',
			Mandatory = $true,
			Position = 2 )]
		[Alias('Config')]
		[hashtable]$Configuration,
		[Parameter(ParameterSetName = 'File',
			Mandatory = $true,
			Position = 2 )]
		[Alias('ConfigFile')]
		[string]$ConfigurationFile,
		[Parameter(ParameterSetName = 'Variables',
			Mandatory = $true,
			Position = 2 )]
		[Parameter(ParameterSetName = 'Hashtable')]
		[Parameter(ParameterSetName = 'File')]
		[AllowNull()][hashtable]$Variables,
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
				if ($pscmdlet.ShouldProcess([System.IO.Path]::GetTempPath(), "Creating new temporary folder")) {
					$workFolder = New-TempWorkspaceFolder
				}
				else {
					$workFolder = "NonExistingPath"
				}
			}
			try {
				$packageFile = [PowerUpConfig]::GetPackageFileName()
				if (!$Unpacked) {
					#Extract package files
					if ($pscmdlet.ShouldProcess($pFile, "Extracting package file to $workFolder")) {
						Expand-ArchiveItem -Path $pFile -DestinationPath $workFolder -Item $packageFile
					}
				}
			
				if ($pscmdlet.ShouldProcess($packageFile, "Reading package file from $workFolder")) {
					$package = [PowerUpPackage]::FromFile((Join-Path $workFolder $packageFile))
				}
				else {
					$package = [PowerUpPackage]::new()
				}
				$configFile = $package.ConfigurationFile

				if (!$Unpacked) {
					if ($pscmdlet.ShouldProcess($configFile, "Extracting config file from $pFile")) {
						Expand-ArchiveItem -Path $pFile -DestinationPath $workFolder -Item $configFile
					}
				}
				
				#Assign new values
				Write-Verbose "Assigning new values to the config"

				if ($PSCmdlet.ParameterSetName -eq 'Value') {
					$newConfig = @{ $ConfigName = $Value }
				}
				elseif ($PSCmdlet.ParameterSetName -eq 'Hashtable') {
					$newConfig = $Configuration
				}
				elseif ($PSCmdlet.ParameterSetName -eq 'File') {
					$newConfig = (Get-PowerUpConfig -Path $ConfigurationFile).AsHashtable()
				}
				#Overriding Variables
				if ($Variables) {
					if ($PSCmdlet.ParameterSetName -ne 'Variables') { $newConfig.Remove('Variables') }
					$newConfig += @{ Variables = $Variables}
				}

				$configTempFile = (Join-Path $workFolder $configFile)
				$configObject = Get-PowerUpConfig -Path $configTempFile -Configuration $newConfig

				if ($pscmdlet.ShouldProcess($configTempFile, "Saving the config file")) {
					$configObject.SaveToFile($configTempFile, $true)
				}
				if (!$Unpacked) {
					if ($pscmdlet.ShouldProcess($pFile, "Updating package with a new config file")) {
						$null = Add-ArchiveItem -Path $pFile -Item $configTempFile
					}
				}
			}
			catch {
				throw $_
			}
			finally {
				if (!$Unpacked -and $workFolder.Name -like 'PowerUpWorkspace*') {
					if ($pscmdlet.ShouldProcess($workFolder, "Removing temporary folder")) {
						Remove-Item $workFolder -Recurse -Force
					}
				}
			}
		}
	}
	end {

	}
}
