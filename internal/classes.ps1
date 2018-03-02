using namespace System.IO
using namespace System.IO.Compression

class PowerUpClass {
	# Shared methods
	[void] SaveToFile ([string]$fileName) {
		$this | ConvertTo-Json -Depth 5 | Out-File $fileName
	}
	[void] SaveToFile ([string]$fileName, [bool]$force) {
		$this | ConvertTo-Json -Depth 5 | Out-File $fileName -Force
	}

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

	hidden [string] SplitRelativePath ([string]$Path, [int]$Depth) {
		$returnPath = Split-Path -Path $Path -Leaf
		$parent = Split-Path -Path $Path -Parent
		while ($Depth-- -gt 0) {
			$returnPath = Join-Path -Path (Split-Path -Path $parent -Leaf) -ChildPath $returnPath
			$parent = Split-Path -Path $parent -Parent
		}
		return $returnPath
	}
	[byte[]] GetBinaryFile ([string]$fileName) {
		$stream = [System.IO.File]::Open($fileName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
		$b = [byte[]]::new($stream.Length)
		$stream.Read($b, 0, $b.Length)
		$stream.Close()
		return $b
	}
	[void] WriteZipFile ([ZipArchive]$zipFile, [string]$fileName, [byte[]]$data) {
		#Remove old file entry if exists
		if ($zipFile.Mode -eq [ZipArchiveMode]::Update) {
			if ($oldEntry = $zipFile.GetEntry($fileName)) {
				$oldEntry.Delete()
			}
		}
		#Create new file entry
		$entry = $zipFile.CreateEntry($fileName)
		$writer = $entry.Open()
		#Write file contents
		$writer.Write($data, 0, $data.Length )
		#Close the stream
		$writer.Close()
	}
	[void] WriteZipFileStream ([ZipArchive]$zipFile, [string]$fileName, [FileStream]$stream) {
		$entry = $zipFile.CreateEntry($fileName)
		$writer = $entry.Open()
		$data = [byte[]]::new(4098)
		#Read from stream and write file contents
		while ($read = $stream.Read($data, 0, $data.Length)) {
			$writer.Write($data, 0, $data.Length )
		}
		#Close the stream
		$writer.Close()
	}
	#Initiates package update saving the current file in the package
	[void] Alter() {
		#Open new file stream
		$writeMode = [System.IO.FileMode]::Open
		$stream = [FileStream]::new($this.Parent.FileName, $writeMode)
		#Open zip file
		$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
		#Write file
		$this.Save($zip)
		#Close archive
		$zip.Dispose()
		$stream.Dispose()
	}
	#Adding file objects to the parent 
	[void] NewFile ([object[]]$FileObject, [string]$CollectionName) {
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
			$f = [PowerUpFile]::new($sourcePath, $this.SplitRelativePath($p.FullName, $depth))
			$this.AddFile($f, $CollectionName)
		}
	}
	[void] NewFile ([string]$FileName, [int]$Depth, [string]$CollectionName) {
		$f = [PowerUpFile]::new($FileName, $this.SplitRelativePath($FileName, $Depth))
		$this.AddFile($f, $CollectionName)
	}
	[void] AddFile ([PowerUpFile[]]$PowerUpFile, [string]$CollectionName) {
		foreach ($file in $PowerUpFile) {
			$file.Parent = $this
			if ($this.$CollectionName -and $this.$CollectionName.GetType() -is [System.Array]) {
				$this.$CollectionName += $file
			}
			elseif ($this.$CollectionName -and $this.$CollectionName.GetType() -is [System.Collections.ArrayList]) {
				$this.$CollectionName.Add($file)
			}
			else {
				$this.$CollectionName = $file
			}
		}
	}
	[PowerUpFile[]] GetFile ([string[]]$PackagePath, [string]$CollectionName) {
		$result = @()
		if ($this.$CollectionName) {
			if ($PackagePath) {
				foreach ($path in $PackagePath) {
					$result += $this.$CollectionName | Where-Object $_.GetPackagePath() -eq $path
				}
			}
			else {
				$result = $this.$CollectionName
			}
		}
		return $result
	}
	[void] RemoveFile ([string[]]$PackagePath, [string]$CollectionName) {
		if ($this.$CollectionName) {
			foreach ($path in $PackagePath) {
				$this.$CollectionName = $this.$CollectionName | Where-Object $_.GetPackagePath() -ne $path
			}
		}
	}
	[void] UpdateFile ([PowerUpFile[]]$PowerUpFile, [string]$CollectionName) {
		foreach ($file in $PowerUpFile) {
			$this.RemoveFile($file.GetPackagePath(), $CollectionName)
			$this.AddFile($file, $CollectionName)
		}
	}
}
class PowerUpPackage : PowerUpClass {
	#Public properties
	[PowerUpBuild[]]$Builds
	[string]$ScriptDirectory
	# [string]$DeployScript
	[PowerUpFile]$DeployFile
	[PowerUpFile]$PostDeployFile
	[PowerUpFile]$PreDeployFile
	[string]$ConfigurationFile
	[PowerUpConfig]$Configuration

	hidden [string]$FileName
	# hidden [string]$DeploySource
	
	#Constructors
	PowerUpPackage () {
		$this.Init()
		# Processing deploy file
		$file = [PowerUpPackage]::GetDeployFile()
		# Adding root deploy file
		$newFile = [PowerUpRootFile]::new($file.FullName, $file.Name)
		$this.AddFile($newFile, 'DeployFile')
	}

	PowerUpPackage ([string]$fileName) {
		if (!(Test-Path $fileName)) {
			throw "File $fileName not found. Aborting."
		}
		$this.FileName = $FileName
		# Writing zip file contents into memory
		$zip = [ZipReader]::new($fileName)

		# Processing package file
		$pkgFile = $zip.Entries | Where-Object Path -eq ([PowerUpConfig]::GetPackageFileName())
		if ($pkgFile) {
			$jsonObject = ConvertFrom-Json $pkgFile.Content -ErrorAction Stop
			$this.Init($jsonObject)
			# Processing builds
			foreach ($build in $jsonObject.builds) {
				$newBuild = [PowerUpBuild]::new($build.build)
				foreach ($script in $build.Scripts) {
					$scriptFile = $zip.Entries | Where-Object Path -eq (Join-Path $this.ScriptDirectory $script.packagePath)
					if (!$scriptFile) {
						$this.ThrowArgumentException($this, "File not found: $script.packagePath")
					}
					$newScript = [PowerUpFile]::new($script, $scriptFile)
					$newBuild.AddScript($newScript, $true)
				}
				$this.AddBuild($newBuild)
			}
			# Processing deploy files
			foreach ($file in @('DeployFile', 'PreDeployFile', 'PostDeployFile')) {
				$jsonFileObject = $jsonObject.$file
				if ($jsonFileObject) {
					$fileBinary = $zip.Entries | Where-Object Path -eq $file.packagePath
					$newFile = [PowerUpRootFile]::new($jsonFileObject, $fileBinary)
					$this.AddFile($newFile, $file)
				}
			}
		}
		else {
			$this.ThrowArgumentException($this, "Incorrect package format: $fileName")
		}

		# Processing configuration file
		$configFile = $zip.Entries | Where-Object Path -eq $this.ConfigurationFile
		if ($configFile) {
			$this.Configuration = [PowerUpConfig]::new($configFile.Content)
			$this.Configuration.Parent = $this
		}
		else {
			$this.ThrowArgumentException($this, "Incorrect package format: $fileName")
		}


	}
	
	# hidden PowerUpPackage ([string]$jsonString) {
	# 	$jsonObject = ConvertFrom-Json $jsonString -ErrorAction Stop
	# 	$this.ScriptDirectory = $jsonObject.ScriptDirectory
	# 	$this.DeployScript = $jsonObject.DeployScript
	# 	$this.PreDeployScript = $jsonObject.PreDeployScript
	# 	$this.PostDeployScript = $jsonObject.PostDeployScript
	# 	$this.DeploySource = $jsonObject.DeploySource
	# 	$this.ConfigurationFile = $jsonObject.ConfigurationFile
	# 	$this.PackageFile = $jsonObject.PackageFile
	# 	foreach ($build in $jsonObject.builds) {
	# 		$newBuild = [PowerUpBuild]::new($build)
	# 		$this.AddBuild($newBuild)
	# 	}
	# }

	#Static Methods
	# static [PowerUpPackage] FromJsonString ([string]$jsonString) {
	# 	return [PowerUpPackage]::new($jsonString)
	# }
	# static [PowerUpPackage] FromFile ([string]$path) {
	# 	if (!(Test-Path $path)) {
	# 		throw "Package file $path not found. Aborting."
	# 	}
	# 	return [PowerUpPackage]::new($path)
	# }

	#Methods
	[void] Init () {
		$this.ScriptDirectory = 'content'
		# $this.DeploySource = ".\bin\Deploy.ps1"
		$this.ConfigurationFile = 'PowerUp.config.json'
		$this.Configuration = [PowerUpConfig]::new()
		$this.Configuration.Parent = $this
	}
	[void] Init ([string]$jsonObject) {
		$this.Init()
		if ($jsonObject) {
			$this.ScriptDirectory = $jsonObject.ScriptDirectory
			# $this.DeployScript = $jsonObject.DeployScript
			# $this.PreDeployScript = $jsonObject.PreDeployScript
			# $this.PostDeployScript = $jsonObject.PostDeployScript
			$this.ConfigurationFile = $jsonObject.ConfigurationFile
			$this.PackageFile = $jsonObject.PackageFile
		}
	}
	[PowerUpBuild[]] GetBuilds ([string]$build) {
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
			return $newBuild
		}
	}

	[array] EnumBuilds () {
		return $this.builds.build
	}
	[string] GetVersion () {
		return $this.Builds[-1].Build
	}
	<#
	[int]GetLastBuildDeployOrder() {
		if ($this.builds) {
			return $this.builds[-1].deployOrder
		}
		else { return 0 }
	}
	#>

	[PowerUpBuild] GetBuild ([string]$build) {
		if ($currentBuild = $this.builds | Where-Object { $_.build -eq $build }) {
			return $currentBuild
		}
		else {
			$this.ThrowArgumentException($this, 'Build not found.')
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
		}
	}
	
	[void] RemoveBuild ([PowerUpBuild]$build) {
		if ($this.builds | Where-Object { $_.build -eq $build.build }) {
			$this.builds = $this.builds | Where-Object { $_.build -ne $build.build }
		}
		else {
			$this.ThrowArgumentException($this, "Build $build not found.")
		}
	}
	[void] RemoveBuild ([string]$build) {
		$this.RemoveBuild($this.GetBuild($build))
	}
	[bool] ScriptExists([string]$fileName) {
		if (!(Test-Path $fileName)) {
			$this.ThrowArgumentException($this, "Path not found: $fileName")
		}
		$hash = (Get-FileHash $fileName).Hash
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
		$hash = (Get-FileHash $fileName).Hash
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
	[bool] PackagePathExists([string]$PackagePath) {
		foreach ($build in $this.builds) {
			if ($build.PackagePathExists($PackagePath)) {
				return $true
			}
		}
		return $false
	}
	[bool] PackagePathExists([string]$fileName, [int]$Depth) {
		foreach ($build in $this.builds) {
			if ($build.PackagePathExists($fileName, $Depth)) {
				return $true
			}
		}
		return $false
	}
	[string] ExportToJson() {
		$fieldsToExport = @(
			'ScriptDirectory'
			'ConfigurationFile'
		)
		foreach ($type in @('DeployFile', 'PreDeployFile', 'PostDeployFile', 'Builds')) {
			$collection = @()
			foreach ($collectionItem in $this.$type) {
				$collection += $collectionItem.ExportToJson() | ConvertFrom-Json
			}
			$fieldsToExport += @{ Name = $type; Expression = {$collection}}
		}
		return $this | Select-Object -Property $fieldsToExport | ConvertTo-Json -Depth 3
	}
	[void] SavePackageFile([ZipArchive]$zipFile) {
		$pkgFileContent = $this.ExportToJson() | ConvertTo-Byte
		$this.WriteZipFile($zipFile, ([PowerUpConfig]::GetPackageFileName()), $pkgFileContent)
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
		#Create zip file
		$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Create)
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

		#Close archive
		$zip.Dispose()
		$stream.Dispose()
	}

	[void] SaveModuleToFile([ZipArchive]$zipArchive) {
		foreach ($file in (Get-PowerUpModuleFileList)) {
			$this.WriteZipFile($zipArchive, (Join-Path "Modules\PowerUp" $file.Path), $this.GetBinaryFile($file.FullName))
		}
	}
	#Returns content folder for scripts
	[string] GetPackagePath() {
		return $this.ScriptDirectory
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
class PowerUpBuild : PowerUpClass {
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
		#$this.deployOrder = $parent.GetLastBuildDeployOrder() + 10
	}

	hidden PowerUpBuild ([psobject]$object) {
		if (!$object.build) {
			$this.ThrowArgumentException($this, 'Build name cannot be empty');
		}
		$this.build = $object.build
		$this.PackagePath = $object.PackagePath
		$this.CreatedDate = $object.CreatedDate
		# foreach ($script in $object.scripts) {
		# 	$newScript = [PowerUpFile]::AddPackageFile($script)
		# 	$this.AddScript($newScript, $true)
		# }
		#$this.deployOrder = $parent.GetLastBuildDeployOrder() + 10
	}

	#Methods 
	[void] NewScript ([object[]]$FileObject) {
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
			$s = [PowerUpFile]::new($sourcePath, $this.SplitRelativePath($p.FullName, $depth))
			$s.Parent = $this
			$this.AddScript($s)
		}
	}
	[void] NewScript ([string]$FileName, [int]$Depth) {
		$s = [PowerUpFile]::new($FileName, $this.SplitRelativePath($FileName, $Depth))
		$s.Parent = $this
		$this.AddScript($s)
	}
	[void] AddScript ([PowerUpFile[]]$script) {
		$this.AddScript($script, $false)
	}
	[void] AddScript ([PowerUpFile[]]$script, [bool]$SkipSourceCheck) {
		foreach ($s in $script) {
			if (!$SkipSourceCheck -and $this.SourcePathExists($s.sourcePath)) {
				$this.ThrowArgumentException($this, "External script $($s.sourcePath) already exists.")
			}
			elseif ($this.PackagePathExists($s.packagePath)) {
				$this.ThrowArgumentException($this, "Script $($s.packagePath) already exists inside this build.")
			}
			else {
				$s.Parent = $this
				$this.scripts += $s
			}
		}
	}
	[string] ToString() {
		return "[Build: $($this.build); Scripts: @{$($this.Scripts.Name -join ', ') }]"
	}
	hidden [bool] HashExists([string]$hash) {
		foreach ($script in $this.Scripts) {
			if ($hash -eq $script.hash) {
				return $true
			}
		}
		return $false
	}
	hidden [bool] HashExists([string]$hash, [string]$sourcePath) {
		foreach ($script in $this.Scripts) {
			if ($script.SourcePath -eq $sourcePath -and $hash -eq $script.hash) {
				return $true
			}
		}
		return $false
	}
	[bool] ScriptExists([string]$fileName) {
		if (!(Test-Path $fileName)) {
			$this.ThrowArgumentException($this, "Path not found: $fileName")
		}
		$hash = (Get-FileHash $fileName).Hash
		return $this.HashExists($hash)
	}
	[bool] ScriptModified([string]$fileName, [string]$sourcePath) {
		if (!(Test-Path $fileName)) {
			$this.ThrowArgumentException($this, "Path not found: $fileName")
		}
		if ($this.SourcePathExists($sourcePath)) {
			$hash = (Get-FileHash $fileName).Hash
			return -not $this.HashExists($hash, $sourcePath)
		}
		else {
			return $false
		}
	}
	[bool] SourcePathExists([string]$path) {
		foreach ($script in $this.Scripts) {
			if ($path -eq $script.sourcePath) {
				return $true
			}
		}
		return $false
	}
	[bool] PackagePathExists([string]$PackagePath) {
		foreach ($script in $this.Scripts) {
			if ($PackagePath -eq $script.packagePath) {
				return $true
			}
		}
		return $false
	}
	[bool] PackagePathExists([string]$fileName, [int]$Depth) {
		$path = $this.SplitRelativePath($fileName, $Depth)
		foreach ($script in $this.Scripts) {
			if ($path -eq $script.packagePath) {
				return $true
			}
		}
		return $false
	}
	[string] GetPackagePath() {
		return Join-Path $this.Parent.GetPackagePath() $this.PackagePath
	}	
	# [string] GetPackagePath([string]$fileName) {
	# 	return $this.GetPackagePath($fileName, 0)
	# }
	# [string] GetPackagePath([string]$fileName, [int]$Depth) {
	# 	return $this.SplitRelativePath($fileName, $Depth)
	# }
	[string] ExportToJson() {
		$scriptCollection = @()
		foreach ($script in $this.Scripts) {
			$scriptCollection += $script.ExportToJson() | ConvertFrom-Json
		}
		$fields = @(
			'Build'
			'CreatedDate'
			'PackagePath'
			@{ Name = 'Scripts'; Expression = {$scriptCollection}}
		)
		return $this | Select-Object -Property $fields | ConvertTo-Json -Depth 2
	}
	#Writes current build into the archive file
	[void] Save([ZipArchive]$zipFile) {
		foreach ($script in $this.Scripts) {
			$script.Save($zipFile)
		}
	}
	#Overload for builds - including module update
	[void] Alter() {
		#Open new file stream
		$writeMode = [System.IO.FileMode]::Open
		$stream = [FileStream]::new($this.Parent.FileName, $writeMode)
		#Open zip file
		$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
		#Write package file
		$this.Parent.SavePackageFile($zip)
		#Write builds
		$this.Save($zip)
		#Write module
		$this.Parent.SaveModuleToFile($zip)
		#Close archive
		$zip.Dispose()
		$stream.Dispose()
	}
}

class PowerUpFile : PowerUpClass {
	#Public properties
	[string]$SourcePath
	[string]$PackagePath
	#[string]$Content
	[int]$Length
	[string]$Name
	[System.DateTimeOffset]$LastWriteTime
	[byte[]]$ByteArray

	#Hidden properties
	hidden [string]$Hash
	hidden [PowerUpClass]$Parent
	
	#Constructors
	PowerUpFile ([string]$SourcePath, [string]$packagePath) {
		if (!(Test-Path $SourcePath)) {
			$this.ThrowArgumentException($this, "Path not found: $SourcePath")
		}
		if (!$packagePath) {
			$this.ThrowArgumentException($this, 'Path inside the package cannot be empty')
		}
		$this.SourcePath = $SourcePath
		$this.packagePath = $packagePath
		$this.Hash = (Get-FileHash $SourcePath).Hash
		$file = Get-Item $SourcePath
		$this.Length = $file.Length
		$this.Name = $file.Name
		$this.LastWriteTime = $file.LastWriteTime
		$this.ByteArray = $this.GetBinaryFile($SourcePath)
	}

	PowerUpFile ([psobject]$object) {
		$this.Init($object)
	}

	PowerUpFile ([psobject]$object, [ZipFileContents]$file) {
		$this.Init($object)
		if ($this.Hash -ne $file.Hash) {
			$this.ThrowArgumentException($this, "File cannot be loaded, hash mismatch: $($file.Name)")
		}
		$this.ByteArray = $file.ByteArray
		$this.Length = $file.Length
		$this.Name = $file.Name
		$this.LastWriteTime = $file.LastWriteTime
	}

	# #Static methods 
	# static [PowerUpFile] AddPackageFile ([psobject]$object) {
	# 	return [PowerUpFile]::new($object)
	# }

	# static [PowerUpFile] AddPackageFile ([psobject]$object) {
	# 	return [PowerUpFile]::new($object)
	# }
	

	#Methods 
	[void] Init ([psobject]$object) {
		if (!$object.packagePath) {
			$this.ThrowArgumentException($this, 'Path inside the package cannot be empty')
		}
		$this.SourcePath = $object.SourcePath
		$this.packagePath = $object.packagePath
		$this.Hash = $object.hash
	}
	[string] ToString() {
		return "$($this.packagePath)"
	}
	[string] GetContent() {
		[byte[]]$Array = $this.ByteArray
		# EF BB BF (UTF8)
		if ( $Array[0] -eq 0xef -and $Array[1] -eq 0xbb -and $Array[2] -eq 0xbf ) {
			$encoding = [System.Text.Encoding]::UTF8
		}
		# FE FF  (UTF-16 Big-Endian)
		elseif ($Array[0] -eq 0xfe -and $Array[1] -eq 0xff) {
			$encoding = [System.Text.Encoding]::BigEndianUnicode
		}
		# FF FE  (UTF-16 Little-Endian)
		elseif ($Array[0] -eq 0xff -and $Array[1] -eq 0xfe) {
			$encoding = [System.Text.Encoding]::Unicode
		}
		# 00 00 FE FF (UTF32 Big-Endian)
		elseif ($Array[0] -eq 0 -and $Array[1] -eq 0 -and $Array[2] -eq 0xfe -and $Array[3] -eq 0xff) {
			$encoding = [System.Text.Encoding]::UTF32
		}
		# FE FF 00 00 (UTF32 Little-Endian)
		elseif ($Array[0] -eq 0xfe -and $Array[1] -eq 0xff -and $Array[2] -eq 0 -and $Array[3] -eq 0) {
			$encoding = [System.Text.Encoding]::UTF32
		}
		elseif ($Array[0] -eq 0x2b -and $Array[1] -eq 0x2f -and $Array[2] -eq 0x76 -and ($Array[3] -eq 0x38 -or $Array[3] -eq 0x39 -or $Array[3] -eq 0x2b -or $Array[3] -eq 0x2f)) {
			$encoding = [System.Text.Encoding]::UTF7
		}
		else {
			$encoding = [System.Text.Encoding]::ASCII
		}
		return $encoding.GetString($Array)
	}
	[string] GetPackagePath() {
		return Join-Path $this.Parent.GetPackagePath() $this.PackagePath
	}		
	[string] ExportToJson() {
		$fields = @(
			'SourcePath'
			'PackagePath'
		)
		return $this | Select-Object -Property $fields | ConvertTo-Json -Depth 1
	}
	#Writes current script into the archive file
	[void] Save([ZipArchive]$zipFile) {
		$this.WriteZipFile($zipFile, $this.GetPackagePath(), $this.ByteArray)
	}
}

class PowerUpRootFile : PowerUpFile {
	#Mirroring base constructors
	PowerUpRootFile ([string]$SourcePath, [string]$packagePath) : base($SourcePath, $packagePath) { }

	PowerUpRootFile ([psobject]$object) : base($object) { }

	PowerUpRootFile ([psobject]$object, [ZipFileContents]$file) : base($object, $file) { }	

	#Overloading GetPackagePath to ignore Script folder
	[string] GetPackagePath() {
		return $this.PackagePath
	}	
}

class PowerUpLog : DbUp.Engine.Output.IUpgradeLog {
	#Hidden properties
	hidden [string]$logToFile
	hidden [bool]$silent
	
	#Constructors
	PowerUpLog ([bool]$silent, [string]$outFile, [bool]$append) {
		$this.silent = $silent
		$this.logToFile = $outFile
		$txt = "Logging started at " + (get-date).ToString()
		if ($outFile) {
			if ($append) {
				$txt | Out-File $this.logToFile -Append
			}
			else {
				$txt | Out-File $this.logToFile -Force
			}
		}
	}
	
	#Methods
	[void] WriteInformation([string]$format, [object[]]$params) {
		if (!$this.silent) {
			Write-Host ($format -f $params)
		}
		if ($this.logToFile) {
			$this.WriteToFile($format, $params)
		}
	}
	[void] WriteError([string]$format, [object[]]$params) {
		if (!$this.silent) {
			Write-Error ($format -f $params)
		}
		if ($this.logToFile) {
			$this.WriteToFile($format, $params)
		}
	}
	[void] WriteWarning([string]$format, [object[]]$params) {
		if (!$this.silent) {
			Write-Warning ($format -f $params)
		}
		if ($this.logToFile) {
			$this.WriteToFile($format, $params)
		}
	}
	[void] WriteToFile([string]$format, [object[]]$params) {
		$format -f $params | Out-File $this.logToFile -Append
	}
}

class PowerUpPackageFile {
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

	#Custom attributes
	[psobject]$Config
	[string]$Version
	[System.Version]$ModuleVersion
	[psobject[]]$Builds

	#Constructors
	PowerUpPackageFile ([FileInfo]$FileObject) {
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
		$this | Add-Member -MemberType AliasProperty -Name Path -Value FullName
		$this | Add-Member -MemberType AliasProperty -Name Size -Value Length
	}
	PowerUpPackageFile ([System.IO.DirectoryInfo]$FileObject) {
		$this.PSPath = $FileObject.PSPath
		$this.PSParentPath = $FileObject.PSParentPath
		$this.PSChildName = $FileObject.PSChildName
		$this.PSDrive = $FileObject.PSDrive
		$this.PSIsContainer = $FileObject.PSIsContainer
		$this.Mode = $FileObject.Mode
		$this.BaseName = $FileObject.BaseName
		$this.Name = $FileObject.Name
		$this.Length = 0
		$this.Directory = $FileObject.Parent
		$this.DirectoryName = $FileObject.Parent.Name
		$this.IsReadOnly = $false
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
		$this | Add-Member -MemberType AliasProperty -Name Path -Value FullName
		$this | Add-Member -MemberType AliasProperty -Name Size -Value Length
	}

	#Methods
	[string] ToString () {
		return $this.FullName
	}
}

class PowerUpConfig : PowerUpClass {
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
				$this.SetValue($property,$jsonConfig.$property)
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
		$this.WriteZipFile($zipFile, $this.Parent.ConfigurationFile, $fileContent)
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

	static [string[]] EnumProperties () {
		return @('ApplicationName', 'SqlInstance', 'Database', 'DeploymentMethod',
			'ConnectionTimeout', 'ExecutionTimeout', 'Encrypt', 'Credential', 'Username',
			'Password', 'SchemaVersionTable', 'Silent', 'Variables'
		)
	}


}