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

}
class PowerUpPackage : PowerUpClass {
	#Public properties
	[PowerUpBuild[]]$Builds
	[string]$ScriptDirectory
	[string]$DeploySource
	[string]$PostDeploySource
	[string]$PreDeploySource
	[string]$DeployScript
	[string]$PostDeployScript
	[string]$PreDeployScript
	[string]$ConfigurationFile
	[string]$PackageFile
	
	#Constructors
	PowerUpPackage () {
		$this.ScriptDirectory = 'content'
		$this.DeployScript = "Deploy.ps1"
		$this.PreDeployScript = "PreDeploy.ps1"
		$this.PostDeployScript = "PostDeploy.ps1"
		$this.DeploySource = "$PSScriptRoot\..\bin\Deploy.ps1"
		$this.ConfigurationFile = 'PowerUp.config.json'
		$this.PackageFile = 'PowerUp.package.json'
	}
	
	hidden PowerUpPackage ([string]$jsonString) {
		$jsonObject = ConvertFrom-Json $jsonString -ErrorAction Stop
		$this.ScriptDirectory = $jsonObject.ScriptDirectory
		$this.DeployScript = $jsonObject.DeployScript
		$this.PreDeployScript = $jsonObject.PreDeployScript
		$this.PostDeployScript = $jsonObject.PostDeployScript
		$this.DeploySource = $jsonObject.DeploySource
		$this.ConfigurationFile = $jsonObject.ConfigurationFile
		$this.PackageFile = $jsonObject.PackageFile
		foreach ($build in $jsonObject.builds) {
			$newBuild = [PowerUpBuild]::new($build)
			$this.AddBuild($newBuild)
		}
	}

	#Static Methods
	static [PowerUpPackage] FromJsonString ([string]$jsonString) {
		return [PowerUpPackage]::new($jsonString)
	}
	static [PowerUpPackage] FromFile ([string]$path) {
		if (!(Test-Path $path)) {
			throw "Package file $path not found. Aborting."
		}
		return [PowerUpPackage]::new((Get-Content $path -Raw -ErrorAction Stop))
	}

	#Methods
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
	[bool] SourcePathExists([string]$fileName) {
		if (!(Test-Path $fileName)) {
			$this.ThrowArgumentException($this, "Path not found: $fileName")
		}
		$path = (Resolve-Path $fileName).Path
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

}
class PowerUpBuild : PowerUpClass {
	#Public properties
	[string]$Build
	[PowerUpFile[]]$Scripts
	[string]$CreatedDate
	
	#Constructors
	PowerUpBuild ([string]$build) {
		if (!$build) {
			$this.ThrowArgumentException($this, 'Build name cannot be empty');
		}
		$this.build = $build
		$this.CreatedDate = (Get-Date).Datetime
		#$this.deployOrder = $parent.GetLastBuildDeployOrder() + 10
	}

	hidden PowerUpBuild ([psobject]$object) {
		if (!$object.build) {
			$this.ThrowArgumentException($this, 'Build name cannot be empty');
		}
		$this.build = $object.build
		$this.CreatedDate = $object.CreatedDate
		foreach ($script in $object.scripts) {
			$newScript = [PowerUpFile]::AddPackageFile($script)
			$this.AddScript($newScript, $true)
		}
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
			$s = New-Object PowerUpFile ($p.FullName, $this.GetPackagePath($p.FullName, $depth))
			$this.AddScript($s)
		}
	}
	[void] NewScript ([string]$FileName, [int]$Depth) {
		$s = New-Object PowerUpFile ($FileName, $this.GetPackagePath($FileName, $Depth))
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
				$this.scripts += $script
			}
		}
	}
	[string] ToString() {
		return "[Build $($this.build)]"
	}
	hidden [bool] HashExists([string]$hash) {
		foreach ($script in $this.Scripts) {
			if ($hash -eq $script.hash) {
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
	[bool] SourcePathExists([string]$fileName) {
		if (!(Test-Path $fileName)) {
			$this.ThrowArgumentException($this, "Path not found: $fileName")
		}
		$path = (Resolve-Path $fileName).Path
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
		$path = $this.GetPackagePath($fileName, $Depth)
		foreach ($script in $this.Scripts) {
			if ($path -eq $script.packagePath) {
				return $true
			}
		}
		return $false
	}
	[string] GetPackagePath([string]$fileName) {
		return $this.GetPackagePath($fileName, 0)
	}
	[string] GetPackagePath([string]$fileName, [int]$Depth) {
		$packagePath = $this.SplitRelativePath($fileName,$Depth)
		return (Join-Path $this.build $packagePath)
	}
}

class PowerUpFile : PowerUpClass {
	#Public properties
	[string]$SourcePath
	[string]$PackagePath

	#Hidden properties
	hidden [string]$Hash
	
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
	}

	hidden PowerUpFile ([psobject]$object) {
		if (!$object.packagePath) {
			$this.ThrowArgumentException($this, 'Path inside the package cannot be empty')
		}
		$this.SourcePath = $object.SourcePath
		$this.packagePath = $object.packagePath
		$this.Hash = $object.hash
	}

	#Static methods 
	static [PowerUpFile] AddPackageFile ([psobject]$object) {
		return [PowerUpFile]::new($object)
	}

	#Methods 
	[string] ToString() {
		return "$($this.packagePath)"
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
	PowerUpPackageFile ([System.IO.FileInfo]$FileObject) {
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

	#Constructors
	PowerUpConfig () {
		$this.Init()
	}
	PowerUpConfig ([string]$jsonString) {
		$this.Init()

		$jsonConfig = $jsonString | ConvertFrom-Json -ErrorAction Stop
		
		foreach ($property in $jsonConfig.psobject.properties.Name) {
			if ($property -in [PowerUpConfig]::EnumProperties()) {
				if ($jsonConfig.$property -ne $null) {
					$this.$property = $jsonConfig.$property
				}
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
		$this.SchemaVersionTable = [NullString]::Value
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