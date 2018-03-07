using namespace System.IO
using namespace System.IO.Compression

######################
# Root class PowerUp #
######################

class PowerUp {
	hidden [void] ThrowException ([string]$exceptionType, [string]$errorText, [object]$object, [System.Management.Automation.ErrorCategory]$errorCategory) {
		$errorMessageObject = [System.Management.Automation.ErrorRecord]::new( `
			(New-Object -TypeName $exceptionType -ArgumentList $errorText),
			"[$($this.gettype().Name)]",
			$errorCategory,
			$object)
		throw $errorMessageObject
	}

	hidden [void] ThrowArgumentException ([object]$object, [string]$message) {
		$this.ThrowException('ArgumentException', $message, $object, 'InvalidArgument')
	}
	#Adding file objects to the parent 
	# hidden [PowerUpFile[]] NewFile ([object[]]$FileObject, [string]$CollectionName) {
		
	# }
	# hidden [PowerUpFile] NewFile ([string]$FileName, [int]$Depth, [string]$CollectionName) {
	# 	$relativePath = [PowerUpHelper]::SplitRelativePath($FileName, $Depth)
	# 	$f = [PowerUpFile]::new($FileName, $relativePath)
	# 	$this.AddFile($f, $CollectionName)
	# 	return $this.GetFile($relativePath, $CollectionName)
	# }
	hidden [PowerUpFile] NewFile ([string]$Name, [string]$PackagePath, [string]$CollectionName) {
		return $this.NewFile($Name, $PackagePath, $CollectionName, [PowerUpFile])
	} 
	hidden [PowerUpFile] NewFile ([string]$Name, [string]$PackagePath, [string]$CollectionName, [type]$Type) {
		$f = $Type::new($Name, $PackagePath)
		$this.AddFile($f, $CollectionName)
		return $this.GetFile($PackagePath, $CollectionName)
	}
	hidden [void] AddFile ([PowerUpFile[]]$PowerUpFile, [string]$CollectionName) {
		foreach ($file in $PowerUpFile) {
			$file.Parent = $this
			if ($CollectionName -notin $this.PsObject.Properties.Name) {
				$this.ThrowArgumentException($this, "$CollectionName is not a valid collection name")
			}
			foreach ($collectionItem in $this.$CollectionName) {
				if ($collectionItem.PackagePath -eq $file.PackagePath) {
					$this.ThrowArgumentException($this, "File $($file.PackagePath) already exists in $($this.ToString()).")
				}
			}
			if (($this.PsObject.Properties | Where-Object Name -eq $CollectionName).TypeNameOfValue -like '*`[`]') {
				$this.$CollectionName += $file
			}
			else {
				$this.$CollectionName = $file
			}
		}
	}
	hidden [PowerUpFile]GetFile ([string]$PackagePath, [string]$CollectionName) {
		if (!$CollectionName) {
			$this.ThrowArgumentException($this, "No collection name provided")
		}
		if (!$PackagePath) {
			$this.ThrowArgumentException($this, 'No path provided')
		}
		return $this.$CollectionName | Where-Object { $_.PackagePath -eq $PackagePath } 
	}
	hidden [void] RemoveFile ([string[]]$PackagePath, [string]$CollectionName) {
		if ($this.$CollectionName) {
			foreach ($path in $PackagePath) {
				$this.$CollectionName = $this.$CollectionName | Where-Object { $_.PackagePath -ne $path }
			}
		}
	}
	hidden [void] UpdateFile ([PowerUpFile[]]$PowerUpFile, [string]$CollectionName) {
		foreach ($file in $PowerUpFile) {
			$this.RemoveFile($file.PackagePath, $CollectionName)
			$this.AddFile($file, $CollectionName)
		}
	}
}

########################
# PowerUpPackage class #
########################

class PowerUpPackage : PowerUp {
	#Public properties
	[PowerUpBuild[]]$Builds
	[string]$ScriptDirectory
	[PowerUpFile]$DeployFile
	[PowerUpFile]$PostDeployFile
	[PowerUpFile]$PreDeployFile
	[PowerUpFile]$ConfigurationFile
	[PowerUpConfig]$Configuration
	[string]$Version
	[System.Version]$ModuleVersion

	#Regular file properties
	[string]$PSPath
	[string]$PSParentPath
	[string]$PSChildName
	[string]$PSDrive
	[bool]  $PSIsContainer
	[string]$Mode
	[string]$BaseName
	[string]$Name
	[int]$Length
	[string]$DirectoryName
	[System.IO.DirectoryInfo]$Directory
	[bool]$IsReadOnly
	[bool]$Exists
	[string]$FullName
	[string]$Extension
	[datetime]$CreationTime
	[datetime]$CreationTimeUtc
	[datetime]$LastAccessTime
	[datetime]$LastAccessTimeUtc
	[datetime]$LastWriteTime
	[datetime]$LastWriteTimeUtc
	[System.IO.FileAttributes]$Attributes

	hidden [string]$FileName
	
	#Constructors
	PowerUpPackage () {
		$this.Init()
		# Processing deploy file
		$file = [PowerUpPackage]::GetDeployFile()
		# Adding root deploy file
		$this.AddFile([PowerUpRootFile]::new($file.FullName, $file.Name), 'DeployFile')
		# Adding configuration file default contents
		$configFile = [PowerUpRootFile]::new()
		$configContent = $this.Configuration.ExportToJson() | ConvertTo-Byte
		$configFile.SetContent($configContent)
		$configFile.PackagePath = [PowerUpConfig]::GetConfigurationFileName()
		$this.AddFile($configFile, 'ConfigurationFile')
	}

	PowerUpPackage ([string]$fileName) {
		if (!(Test-Path $fileName -PathType Leaf)) {
			throw "File $fileName not found. Aborting."
		}
		$this.FileName = $fileName
		# Setting regular file properties
		$this.RefreshFileProperties()
		# Reading zip file contents into memory
		$zip = [Zipfile]::OpenRead($fileName)
		try { 
			# Processing package file
			$pkgFile = $zip.Entries | Where-Object FullName -eq ([PowerUpConfig]::GetPackageFileName())
			if ($pkgFile) {
				$pFile = [PowerUpFile]::new()
				$pFile.SetContent([PowerUpHelper]::ReadDeflateStream($pkgFile.Open()).ToArray())
				$jsonObject = ConvertFrom-Json $pFile.GetContent() -ErrorAction Stop
				$this.Init($jsonObject)
				# Processing builds
				foreach ($build in $jsonObject.builds) {
					$newBuild = $this.NewBuild($build.build)
					foreach ($script in $build.Scripts) {
						$filePackagePath = Join-Path $newBuild.GetPackagePath() $script.packagePath
						$scriptFile = $zip.Entries | Where-Object FullName -eq $filePackagePath
						if (!$scriptFile) {
							$this.ThrowArgumentException($this, "File not found inside the package: $filePackagePath")
						}
						$newScript = [PowerUpScriptFile]::new($script, $scriptFile)
						$newBuild.AddScript($newScript, $true)
					}
				}
				# Processing root files
				foreach ($file in @('DeployFile', 'PreDeployFile', 'PostDeployFile', 'ConfigurationFile')) {
					$jsonFileObject = $jsonObject.$file
					if ($jsonFileObject) {
						$fileBinary = $zip.Entries | Where-Object FullName -eq $jsonFileObject.packagePath
						if ($fileBinary) {
							$newFile = [PowerUpRootFile]::new($jsonFileObject, $fileBinary)
							$this.AddFile($newFile, $file)
						}
						else {
							$this.ThrowException('Exception', "File $($jsonFileObject.packagePath) not found in the package", $this, 'InvalidData')
						}
					}
				}
			}
			else {
				$this.ThrowArgumentException($this, "Incorrect package format: $fileName")
			}

			# Processing configuration file
			if ($this.ConfigurationFile) {
				$this.Configuration = [PowerUpConfig]::new($this.ConfigurationFile.GetContent())
				$this.Configuration.Parent = $this
			}
		}
		catch { throw $_ }
		finally {
			# Dispose of the reader
			$zip.Dispose()
		}
	}
	
	#Methods
	[void] Init () {
		$this.ScriptDirectory = 'content'
		# $this.DeploySource = ".\bin\Deploy.ps1"
		# $this.ConfigurationFile = 'PowerUp.config.json'
		$this.Configuration = [PowerUpConfig]::new()
		$this.Configuration.Parent = $this
	}
	[void] Init ([object]$jsonObject) {
		$this.Init()
		if ($jsonObject) {
			$this.ScriptDirectory = $jsonObject.ScriptDirectory
		}
	}
	[void] RefreshFileProperties() {
		if ($this.FileName) {
			$FileObject = Get-Item $this.FileName
			$this.PSPath = $FileObject.PSPath
			$this.PSParentPath = $FileObject.PSParentPath
			$this.PSChildName = $FileObject.PSChildName
			$this.PSDrive = $FileObject.PSDrive
			$this.PSIsContainer = $FileObject.PSIsContainer
			$this.Mode = $FileObject.Mode
			$this.BaseName = $FileObject.BaseName
			$this.Name = $FileObject.Name
			$this.Length = $FileObject.Length
			$this.DirectoryName = $FileObject.DirectoryName
			$this.Directory = $FileObject.Directory
			$this.IsReadOnly = $FileObject.IsReadOnly
			$this.Exists = $FileObject.Exists
			$this.FullName = $FileObject.FullName
			$this.Extension = $FileObject.Extension
			$this.CreationTime = $FileObject.CreationTime
			$this.CreationTimeUtc = $FileObject.CreationTimeUtc
			$this.LastAccessTime = $FileObject.LastAccessTime
			$this.LastAccessTimeUtc = $FileObject.LastAccessTimeUtc
			$this.LastWriteTime = $FileObject.LastWriteTime
			$this.LastWriteTimeUtc = $FileObject.LastWriteTimeUtc
			$this.Attributes = $FileObject.Attributes

			# Also refresh PowerUp module version from the archive
			$this.RefreshModuleVersion()
		}
	}
	[PowerUpBuild[]] GetBuilds () {
		return $this.Builds
	}
	[PowerUpBuild] NewBuild ([string]$build) {
		if (!$build) {
			$this.ThrowArgumentException($this, 'Build name is not specified.')
			return $null
		}
		if ($this.builds | Where-Object { $_.build -eq $build }) {
			$this.ThrowArgumentException($this, "Build $build already exists.")
			return $null
		}
		else {
			$newBuild = [PowerUpBuild]::new($build)
			$newBuild.Parent = $this
			$this.builds += $newBuild
			$this.Version = $newBuild.Build
			return $newBuild
		}
	}

	[array] EnumBuilds () {
		return $this.builds.build
	}
	[string] GetVersion () {
		return $this.Version
	}
	
	[PowerUpBuild] GetBuild ([string]$build) {
		if ($currentBuild = $this.builds | Where-Object { $_.build -eq $build }) {
			return $currentBuild
		}
		else {
			# $this.ThrowArgumentException($this, 'Build not found.')
			return $null
		}
	}
	[void] AddBuild ([PowerUpBuild]$build) {
		if ($this.builds | Where-Object { $_.build -eq $build.build }) {
			$this.ThrowArgumentException($this, "Build $build already exists.")
		}
		else {
			$build.Parent = $this
			$this.builds += $build
			$this.Version = $build.Build
		}
	}
	
	[void] RemoveBuild ([PowerUpBuild]$build) {
		if ($this.builds | Where-Object { $_.build -eq $build.build }) {
			$this.builds = $this.builds | Where-Object { $_.build -ne $build.build }
		}
		else {
			$this.ThrowArgumentException($this, "Build $build not found.")
		}
		if ($this.Builds) {
			$this.Version = $this.Builds[-1].Build
		}
		else {
			$this.Version = [NullString]::Value
		}
	}
	[void] RemoveBuild ([string]$build) {
		$this.RemoveBuild($this.GetBuild($build))
	}
	[bool] ScriptExists([string]$fileName) {
		if (!(Test-Path $fileName)) {
			$this.ThrowArgumentException($this, "Path not found: $fileName")
		}
		$hash = [PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($fileName)))
		foreach ($build in $this.builds) {
			if ($build.HashExists($hash)) {
				return $true
			}
		}
		return $false
	}
	[bool] ScriptModified([string]$fileName, [string]$sourcePath) {
		if (!(Test-Path $fileName)) {
			$this.ThrowArgumentException($this, "Path not found: $fileName")
		}
		$hash = [PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($fileName)))
		foreach ($build in $this.builds) {
			if ($build.SourcePathExists($sourcePath)) {
				if (!$build.HashExists($hash, $sourcePath)) {
					return $true
				}
				break
			}
		}
		return $false
	}
	[bool] SourcePathExists([string]$path) {
		foreach ($build in $this.builds) {
			if ($build.SourcePathExists($path)) {
				return $true
			}
		}
		return $false
	}
	# [bool] PackagePathExists([string]$PackagePath) {
	# 	foreach ($build in $this.builds) {
	# 		if ($build.PackagePathExists($PackagePath)) {
	# 			return $true
	# 		}
	# 	}
	# 	return $false
	# }
	# [bool] PackagePathExists([string]$fileName, [int]$Depth) {
	# 	foreach ($build in $this.builds) {
	# 		if ($build.PackagePathExists($fileName, $Depth)) {
	# 			return $true
	# 		}
	# 	}
	# 	return $false
	# }
	[string] ExportToJson() {
		$exportObject = @{} | Select-Object 'ScriptDirectory', 'DeployFile', 'PreDeployFile', 'PostDeployFile', 'ConfigurationFile', 'Builds'
		foreach ($type in $exportObject.psobject.Properties.name) {
					
			if ($this.$type -is [PowerUp]) {
				$exportObject.$type = $this.$type.ExportToJson() | ConvertFrom-Json
			}
			elseif ($this.$type -is [System.Array] -or $this.$type -is [System.Collections.ArrayList]) {
				$collection = @()
				foreach ($collectionItem in $this.$type) {
					if ($collectionItem -is [PowerUp]) {
						$collection += $collectionItem.ExportToJson() | ConvertFrom-Json
					}
					else {
						$collection += $collectionItem
					}
				}
				$exportObject.$type = $collection
			}
			else {
				$exportObject.$type = $this.$type
			}
			
		}
		return $exportObject | ConvertTo-Json -Depth 3
	}
	hidden [void] SavePackageFile([ZipArchive]$zipFile) {
		$pkgFileContent = $this.ExportToJson() | ConvertTo-Byte
		[PowerUpHelper]::WriteZipFile($zipFile, ([PowerUpConfig]::GetPackageFileName()), $pkgFileContent)
	}
	[void] Alter() {
		$this.SaveToFile($this.FileName, $true)
	}
	[void] Save() {
		$this.SaveToFile($this.FileName, $true)
	}
	[void] SaveToFile([string]$fileName) {
		$this.SaveToFile($fileName, $false)
	}
	[void] SaveToFile([string]$fileName, [bool]$force) {
		#Open new file stream
		$writeMode = switch ($force) {
			$true { [System.IO.FileMode]::Create }
			default { [System.IO.FileMode]::CreateNew }
		}
		$stream = [FileStream]::new($fileName, $writeMode)
		try {
			#Create zip file
			$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Create)
			try {
				#Change package file name in the object
				$this.FileName = $fileName
				#Write package file
				$this.SavePackageFile($zip)
				#Write files
				foreach ($type in @('DeployFile', 'PreDeployFile', 'PostDeployFile', 'Builds')) {
					foreach ($collectionItem in $this.$type) {
						$collectionItem.Save($zip)
					}
				}

				#Write configs
				$this.Configuration.Save($zip)

				#Write module
				$this.SaveModuleToFile($zip)
			}
			catch { throw $_ }
			finally { $zip.Dispose() } 
		}
		catch {	throw $_ }
		finally { $stream.Dispose() }

		# Setting regular file properties
		$this.RefreshFileProperties()
	}

	hidden [void] SaveModuleToFile([ZipArchive]$zipArchive) {
		foreach ($file in (Get-PowerUpModuleFileList)) {
			[PowerUpHelper]::WriteZipFile($zipArchive, (Join-Path "Modules\PowerUp" $file.Path), [PowerUpHelper]::GetBinaryFile($file.FullName))
		}
	}
	#Returns content folder for scripts
	[string] GetPackagePath() {
		return $this.ScriptDirectory
	}

	#Refresh module version from the module file inside the package
	[void] RefreshModuleVersion() {
		if ($this.FileName) {
			$packagePath = 'Modules\PowerUp\PowerUp.psd1'
			$contents = ([PowerUpHelper]::GetArchiveItem($this.FileName, $packagePath)).ByteArray
			if ([PowerUpHelper]::DecodeBinaryText($contents) -match "[\s+]ModuleVersion[\s+]\=[\s+]\'(.*)\'") {
				$this.ModuleVersion = [System.Version]$Matches[1]
			}
		}
	}

	#Standard ToString() method
	[string] ToString () {
		if ($this.FullName) {
			return $this.FullName
		}
		else {
			return "PowerUpPackage"
		}
	}

	#Sets package configuration
	[void] SetConfiguration([PowerUpConfig]$config) {
		$this.Configuration = $config
		$config.Parent = $this
	}

	#Static methods
	#Returns deploy file name
	static [object]GetDeployFile() {
		return (Get-PowerUpModuleFileList | Where-Object { $_.Type -eq 'Misc' -and $_.Name -eq "Deploy.ps1"})
	}

}

######################
# PowerUpBuild class #
######################

class PowerUpBuild : PowerUp {
	#Public properties
	[string]$Build
	[PowerUpFile[]]$Scripts
	[string]$CreatedDate
	
	hidden [PowerUpPackage]$Parent
	hidden [string]$PackagePath
	
	#Constructors
	PowerUpBuild ([string]$build) {
		if (!$build) {
			$this.ThrowArgumentException($this, 'Build name cannot be empty');
		}
		$this.build = $build
		$this.PackagePath = $build
		$this.CreatedDate = (Get-Date).Datetime
	}

	hidden PowerUpBuild ([psobject]$object) {
		if (!$object.build) {
			$this.ThrowArgumentException($this, 'Build name cannot be empty');
		}
		$this.build = $object.build
		$this.PackagePath = $object.PackagePath
		$this.CreatedDate = $object.CreatedDate
	}

	#Methods 
	#Creates a new script and returns it as an object
	[PowerUpFile[]] NewScript ([object[]]$FileObject) {
		[PowerUpFile[]]$output = @()
		foreach ($p in $FileObject) {
			if ($p.Depth) {
				$depth = $p.Depth
			}
			else {
				$depth = 0
			}
			if ($p.SourcePath) {
				$sourcePath = $p.SourcePath
			}
			else {
				$sourcePath = $p.FullName
			}
			$relativePath = [PowerUpHelper]::SplitRelativePath($sourcePath, $depth)
			$output += $this.NewFile($sourcePath, $relativePath, 'Scripts', [PowerUpScriptFile])
		}
		return $output
	}
	[PowerUpFile] NewScript ([string]$FileName, [int]$Depth) {
		$relativePath = [PowerUpHelper]::SplitRelativePath($FileName, $Depth)
		if ($this.SourcePathExists($relativePath)) {
			$this.ThrowArgumentException($this, "External script $($relativePath) already exists.")
		}
		return $this.NewFile($FileName, $relativePath, 'Scripts', [PowerUpScriptFile])
	}
	# Adds script to the current build
	[void] AddScript ([PowerUpFile[]]$script) {
		$this.AddScript($script, $false)
	}
	[void] AddScript ([PowerUpFile[]]$script, [bool]$Force) {
		foreach ($s in $script) {
			if (!$Force -and $this.SourcePathExists($s.SourcePath)) {
				$this.ThrowArgumentException($this, "External script $($s.SourcePath) already exists.")
			}
			else {
				$this.AddFile($s, 'Scripts')
			}
		}
	}
	[string] ToString() {
		return "[Build: $($this.build); Scripts: @{$($this.Scripts.Name -join ', ')}]"
	}
	#Searches for a certain hash value within the build
	hidden [bool] HashExists([string]$hash) {
		foreach ($script in $this.Scripts) {
			if ($hash -eq $script.hash) {
				return $true
			}
		}
		return $false
	}
	#Searches for a certain hash value within the build for a specific source file
	hidden [bool] HashExists([string]$hash, [string]$sourcePath) {
		foreach ($script in $this.Scripts) {
			if ($script.SourcePath -eq $sourcePath -and $hash -eq $script.hash) {
				return $true
			}
		}
		return $false
	}
	#Compares file hash and returns true if such has has been found within the build
	[bool] ScriptExists([string]$fileName) {
		if (!(Test-Path $fileName)) {
			$this.ThrowArgumentException($this, "Path not found: $fileName")
		}
		$hash = [PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($fileName)))
		return $this.HashExists($hash)
	}
	#Returns true if the file was modified since it last has been added to the build
	[bool] ScriptModified([string]$fileName, [string]$sourcePath) {
		if (!(Test-Path $fileName)) {
			$this.ThrowArgumentException($this, "Path not found: $fileName")
		}
		if ($this.SourcePathExists($sourcePath)) {
			$hash = [PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($fileName)))
			return -not $this.HashExists($hash, $sourcePath)
		}
		else {
			return $false
		}
	}
	#Verify if the file has already been added to the build
	[bool] SourcePathExists([string]$path) {
		foreach ($script in $this.Scripts) {
			if ($path -eq $script.sourcePath) {
				return $true
			}
		}
		return $false
	}
	#Verify if Package Path is already used by a different file
	[bool] PackagePathExists([string]$PackagePath) {
		foreach ($script in $this.Scripts) {
			if ($PackagePath -eq $script.PackagePath) {
				return $true
			}
		}
		return $false
	}
	[bool] PackagePathExists([string]$fileName, [int]$Depth) {
		return $this.PackagePathExists([PowerUpHelper]::SplitRelativePath($fileName, $Depth))
	}
	#Get absolute path inside the package
	[string] GetPackagePath() {
		return Join-Path $this.Parent.GetPackagePath() $this.PackagePath
	}
	#Exports object to Json in the format in which it will be stored in the package file
	[string] ExportToJson() {
		$scriptCollection = @()
		foreach ($script in $this.Scripts) {
			$scriptCollection += $script.ExportToJson() | ConvertFrom-Json
		}
		$fields = @(
			'Build'
			'CreatedDate'
			'PackagePath'
			@{ Name = 'Scripts'; Expression = { $scriptCollection }}
		)
		return $this | Select-Object -Property $fields | ConvertTo-Json -Depth 2
	}
	#Writes current build into the archive file
	hidden [void] Save([ZipArchive]$zipFile) {
		foreach ($script in $this.Scripts) {
			$script.Save($zipFile)
		}
	}
	#Alter build - includes module updates and scripts
	[void] Alter() {
		#Open new file stream
		$writeMode = [System.IO.FileMode]::Open
		$stream = [FileStream]::new($this.Parent.FileName, $writeMode)
		try {
			#Open zip file
			$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
			try {
				#Write package file
				$this.Parent.SavePackageFile($zip)
				#Write builds
				$this.Save($zip)
				#Write module
				$this.Parent.SaveModuleToFile($zip)
			}
			catch { throw $_ }
			finally { $zip.Dispose() }	
		}
		catch { throw $_ }
		finally { $stream.Dispose()	}

		# Refreshing regular file properties for parent object
		$this.Parent.RefreshFileProperties()
	}
}

#####################
# PowerUpFile class #
#####################

class PowerUpFile : PowerUp {
	#Public properties
	[string]$SourcePath
	[string]$PackagePath
	[int]$Length
	[string]$Name
	[string]$LastWriteTime
	[byte[]]$ByteArray

	#Hidden properties
	hidden [string]$Hash
	hidden [PowerUp]$Parent
	
	#Constructors
	PowerUpFile () {}
	PowerUpFile ([string]$SourcePath, [string]$PackagePath) {
		if (!(Test-Path $SourcePath)) {
			$this.ThrowArgumentException($this, "Path not found: $SourcePath")
		}
		if (!$PackagePath) {
			$this.ThrowArgumentException($this, 'Path inside the package cannot be empty')
		}
		$this.SourcePath = $SourcePath
		$this.PackagePath = $PackagePath
		$file = Get-Item $SourcePath
		$this.Length = $file.Length
		$this.Name = $file.Name
		$this.LastWriteTime = $file.LastWriteTime
		$this.ByteArray = [PowerUpHelper]::GetBinaryFile($SourcePath)
	}

	PowerUpFile ([psobject]$fileDescription) {
		$this.Init($fileDescription)
	}

	PowerUpFile ([psobject]$fileDescription, [ZipArchiveEntry]$file) {
		#Set properties imported from package file
		$this.Init($fileDescription)

		#Set properties from Zip archive
		$this.Name = $file.Name
		$this.LastWriteTime = $file.LastWriteTime

		#Read deflate stream and set other properties
		$stream = [PowerUpHelper]::ReadDeflateStream($file.Open())
		try {
			$this.ByteArray = $stream.ToArray()
		}
		catch {
			throw $_
		}
		finally {
			$stream.Dispose()
		}
		
		$this.Length = $this.ByteArray.Length
	}

	#Methods 
	[void] Init ([psobject]$fileDescription) {
		if (!$fileDescription.PackagePath) {
			$this.ThrowArgumentException($this, 'Path inside the package cannot be empty')
		}
		$this.SourcePath = $fileDescription.SourcePath
		$this.PackagePath = $fileDescription.PackagePath
	}
	[string] ToString() {
		return "$($this.PackagePath)"
	}
	[string] GetContent() {
		return [PowerUpHelper]::DecodeBinaryText($this.ByteArray)
	}
	[string] GetPackagePath() {
		return Join-Path $this.Parent.GetPackagePath() $this.PackagePath
	}		
	[string] ExportToJson() {
		$fields = @(
			'SourcePath'
			'Hash'
			'PackagePath'
		)
		return $this | Select-Object -Property $fields | ConvertTo-Json -Depth 1
	}
	#Writes current script into the archive file
	[void] Save([ZipArchive]$zipFile) {
		[PowerUpHelper]::WriteZipFile($zipFile, $this.GetPackagePath(), $this.ByteArray)
	}
	#Updates package content
	[void] SetContent([byte[]]$Array) {
		$this.ByteArray = $Array
	}
	#Initiates package update saving the current file in the package
	[void] Alter() {
		#Open new file stream
		$writeMode = [System.IO.FileMode]::Open
		if ($this.Parent -is [PowerUpBuild]) {
			$pkgObj = $this.Parent.Parent
		}
		elseif ($this.Parent -is [PowerUpPackage]) {
			$pkgObj = $this.Parent
		}
		else {
			$pkgObj = $null
		}
		$stream = [FileStream]::new($pkgObj.FileName, $writeMode, [System.IO.FileAccess]::ReadWrite)
		try {
			#Open zip file
			$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
			try {
				#Write file
				$this.Save($zip)
				#Update package file
				$pkgObj.SavePackageFile($zip)
			}
			catch { throw $_ }
			finally { $zip.Dispose() }	
		}
		catch { throw $_ }
		finally { $stream.Dispose()	}

		# Refreshing regular file properties for parent object
		if ($pkgObj) {
			$pkgObj.RefreshFileProperties()
		}
	}
}


#########################
# PowerUpRootFile class #
#########################

#Ignores the parent package path

class PowerUpRootFile : PowerUpFile {
	#Mirroring base constructors
	PowerUpRootFile () : base () { }
	PowerUpRootFile ([string]$SourcePath, [string]$PackagePath) : base($SourcePath, $PackagePath) { }

	PowerUpRootFile ([psobject]$fileDescription) : base($fileDescription) { }

	PowerUpRootFile ([psobject]$fileDescription, [ZipArchiveEntry]$file) : base($fileDescription, $file) { }	

	#Overloading GetPackagePath to ignore folders of the parent objects
	[string] GetPackagePath() {
		return $this.PackagePath
	}	
}

###########################
# PowerUpScriptFile class #
###########################

#Keeps track of file hash and disallows its creation when hash does not match

class PowerUpScriptFile : PowerUpFile {
	#Mirroring base constructors
	PowerUpScriptFile () : base () { }
	PowerUpScriptFile ([string]$SourcePath, [string]$PackagePath) : base($SourcePath, $PackagePath) {
		$this.Hash = [PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($SourcePath)))
	}

	PowerUpScriptFile ([psobject]$fileDescription) : base($fileDescription) {
		$this.Hash = $fileDescription.Hash
	}

	PowerUpScriptFile ([psobject]$fileDescription, [ZipArchiveEntry]$file) : base($fileDescription, $file) {
		$this.Hash = $fileDescription.Hash
		$fileHash = [PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash($this.ByteArray))
		
		if ($this.Hash -ne $fileHash) {
			$this.ThrowArgumentException($fileDescription, "File cannot be loaded, hash mismatch: $($file.Name)")
		}
	}	
	#Updates file content - overloaded to handle Hashes
	[void] SetContent([byte[]]$Array) {
		$this.ByteArray = $Array
		$this.Hash = [PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash($Array))
	}
}

#######################
# PowerUpConfig class #
#######################

class PowerUpConfig : PowerUp {
	#Properties
	[string]$ApplicationName
	[string]$SqlInstance
	[string]$Database
	[string]$DeploymentMethod
	[System.Nullable[int]]$ConnectionTimeout
	[System.Nullable[int]]$ExecutionTimeout
	[System.Nullable[bool]]$Encrypt
	[pscredential]$Credential
	[string]$Username
	[string]$Password
	[string]$SchemaVersionTable
	[System.Nullable[bool]]$Silent
	[psobject]$Variables

	hidden [PowerUpPackage]$Parent

	#Constructors
	PowerUpConfig () {
		$this.Init()
	}
	PowerUpConfig ([string]$jsonString) {
		$this.Init()

		$jsonConfig = $jsonString | ConvertFrom-Json -ErrorAction Stop
		
		foreach ($property in $jsonConfig.psobject.properties.Name) {
			if ($property -in [PowerUpConfig]::EnumProperties()) {
				$this.SetValue($property, $jsonConfig.$property)
			}
			else {
				$this.ThrowArgumentException($this, "$property is not a valid configuration item")
			}
		}
	}
	#Hidden methods 
	hidden [void] Init () {
		#Defining default values
		$this.ApplicationName = [NullString]::Value
		$this.SqlInstance = [NullString]::Value
		$this.Database = [NullString]::Value
		$this.DeploymentMethod = [NullString]::Value
		$this.Username = [NullString]::Value
		$this.Password = [NullString]::Value
		$this.SchemaVersionTable = 'dbo.SchemaVersions'
	}

	#Methods 
	[hashtable] AsHashtable () {
		$ht = @{}
		foreach ($property in $this.psobject.Properties.Name) {
			$ht += @{ $property = $this.$property }
		}
		return $ht
	}

	[void] SetValue ([string]$Property, [object]$Value) {
		if ([PowerUpConfig]::EnumProperties() -notcontains $Property) {
			$this.ThrowArgumentException($this, "$Property is not a valid configuration item")
		}
		if ($Value -eq $null -and $Property -in @('ApplicationName', 'SqlInstance', 'Database', 'DeploymentMethod', 'Username', 'Password', 'SchemaVersionTable')) {
			$this.$Property = [NullString]::Value
		}
		else {
			$this.$Property = $Value
		}
	}
	# Returns a JSON string representin the object
	[string] ExportToJson() {
		return $this | Select-Object -Property ([PowerUpConfig]::EnumProperties()) | ConvertTo-Json -Depth 2
	}
	[void] Save([ZipArchive]$zipFile) {
		$fileContent = $this.ExportToJson() | ConvertTo-Byte
		if ($this.Parent.ConfigurationFile) {
			$filePath = $this.Parent.ConfigurationFile.PackagePath
		}
		else {
			$filePath = [PowerUpConfig]::GetConfigurationFileName()
			$newFile = [PowerUpRootFile]::new(@{PackagePath = $filePath})
			$this.Parent.AddFile($newFile, 'ConfigurationFile')
		}
		$this.Parent.ConfigurationFile.SetContent($fileContent)
		[PowerUpHelper]::WriteZipFile($zipFile, $filePath, $fileContent)
	}

	#Static Methods
	static [PowerUpConfig] FromJsonString ([string]$jsonString) {
		return [PowerUpConfig]::new($jsonString)
	}
	static [PowerUpConfig] FromFile ([string]$path) {
		if (!(Test-Path $path)) {
			throw "Config file $path not found. Aborting."
		}
		return [PowerUpConfig]::FromJsonString((Get-Content $path -Raw -ErrorAction Stop))
	}

	static [string] GetPackageFileName () {
		return 'PowerUp.package.json'
	}

	static [string] GetConfigurationFileName () {
		return 'PowerUp.config.json'
	}

	static [string[]] EnumProperties () {
		return @('ApplicationName', 'SqlInstance', 'Database', 'DeploymentMethod',
			'ConnectionTimeout', 'ExecutionTimeout', 'Encrypt', 'Credential', 'Username',
			'Password', 'SchemaVersionTable', 'Silent', 'Variables'
		)
	}
}
