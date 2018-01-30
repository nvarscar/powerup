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
		$PSCmdlet.ThrowTerminatingError($errorMessageObject)
	}

	hidden [void] ThrowArgumentException ([string]$message, [object]$object) {
		$this.ThrowException('ArgumentException', $message, $object, 'InvalidArgument')
	}

	hidden [string] RelativePathReplace ([string]$path, [string]$relativePath) {
		return $this.PathReplace($path.Replace($relativePath, '').TrimStart('\'))
	}

	hidden  [string] PathReplace ([string]$path) {
		return (($path -replace '\:', '\') -replace '\\\\', '\') -replace '^\.\\', ''
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
			$this.ThrowArgumentException('Build name is not specified.', $build)
			return $null
		}
		if ($currentBuild = $this.builds | Where-Object { $_.build -eq $build }) {
			$this.ThrowArgumentException("Build $build already exists.", $build)
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
			$this.ThrowArgumentException('Build not found.', $build)
			return $null
		}
	}
	[void] AddBuild ([PowerUpBuild]$build) {
		if ($currentBuild = $this.builds | Where-Object { $_.build -eq $build.build }) {
			$this.ThrowArgumentException("Build $build already exists.", $build)
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
			$this.ThrowArgumentException("Build $build not found.", $build)
		}
	}
	[void] RemoveBuild ([string]$build) {
		$this.RemoveBuild($this.GetBuild($build))
	}
	[bool] ScriptExists([string]$fileName) {
		if (!(Test-Path $fileName)) {
			$this.ThrowArgumentException("Path not found: $fileName")
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
			$this.ThrowArgumentException("Path not found: $fileName")
		}
		$path = (Resolve-Path $fileName).Path
		foreach ($build in $this.builds) {
			if ($build.SourcePathExists($path)) {
				return $true
			}
		}
		return $false
	}
	[bool] PackagePathExists([string]$fileName) {
		foreach ($build in $this.builds) {
			if ($build.PackagePathExists($fileName)) {
				return $true
			}
		}
		return $false
	}
	[bool] PackagePathExists([string]$fileName, [string]$relativePath) {
		foreach ($build in $this.builds) {
			if ($build.PackagePathExists($fileName, $relativePath)) {
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
			$this.ThrowArgumentException('Build name cannot be empty');
		}
		$this.build = $build
		$this.CreatedDate = (Get-Date).Datetime
		#$this.deployOrder = $parent.GetLastBuildDeployOrder() + 10
	}

	hidden PowerUpBuild ([psobject]$object) {
		if (!$object.build) {
			$this.ThrowArgumentException('Build name cannot be empty');
		}
		$this.build = $object.build
		$this.CreatedDate = $object.CreatedDate
		foreach ($script in $object.scripts) {
			$newScript = [PowerUpFile]::AddPackageFile($script)
			$this.AddScript($newScript)
		}
		#$this.deployOrder = $parent.GetLastBuildDeployOrder() + 10
	}

	#Methods 
	[void] NewScript ([string[]]$fileName) {
		foreach ($p in $fileName) {
			if ($currentFile = $this.scripts | Where-Object { $_.sourcePath -eq $p }) {
				$this.ThrowArgumentException("Script $p already exists.");
			}
			else {
				$packagePath = $this.GetPackagePath($p)
				$s = New-Object PowerUpFile ($p, $packagePath)
				$this.scripts += $s
			}
		}
	}
	[void] NewScript ([string]$fileName, [string]$relativePath) {
		if ($currentFile = $this.scripts | Where-Object { $_.sourcePath -eq $fileName }) {
			$this.ThrowArgumentException("Script $fileName already exists.")
		}
		else {
			$packagePath = $this.GetPackagePath($fileName, $relativePath)
			$s = New-Object PowerUpFile ($fileName, $packagePath)
			$this.scripts += $s
		}
	}
	[void] AddScript ([PowerUpFile[]]$script) {
		foreach ($s in $script) {
			if ($this.scripts | Where-Object { $_.sourcePath -eq $s.sourcePath }) {
				$this.ThrowArgumentException("External script $($s.sourcePath) already exists.")
			}
			elseif ($this.scripts | Where-Object { $_.packagePath -eq $s.packagePath }) {
				$this.ThrowArgumentException("Script $($s.packagePath) already exists inside this build.")
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
			$this.ThrowArgumentException("Path not found: $fileName")
		}
		$hash = (Get-FileHash $fileName).Hash
		return $this.HashExists($hash)
	}
	[bool] SourcePathExists([string]$fileName) {
		if (!(Test-Path $fileName)) {
			$this.ThrowArgumentException("Path not found: $fileName")
		}
		$path = (Resolve-Path $fileName).Path
		foreach ($script in $this.Scripts) {
			if ($path -eq $script.sourcePath) {
				return $true
			}
		}
		return $false
	}
	[bool] PackagePathExists([string]$fileName) {
		$path = $this.GetPackagePath($fileName)
		foreach ($script in $this.Scripts) {
			if ($path -eq $script.packagePath) {
				return $true
			}
		}
		return $false
	}
	[bool] PackagePathExists([string]$fileName, [string]$relativePath) {
		$path = $this.GetPackagePath($fileName, $relativePath)
		foreach ($script in $this.Scripts) {
			if ($path -eq $script.packagePath) {
				return $true
			}
		}
		return $false
	}
	[string] GetPackagePath([string]$fileName) {
		$packagePath = $this.PathReplace($fileName)
		return (Join-Path $this.build $packagePath)
	}
	[string] GetPackagePath([string]$fileName, [string]$relativePath) {
		$packagePath = $this.RelativePathReplace($fileName,$relativePath)
		return (Join-Path $this.build $packagePath)
	}
}

class PowerUpFile : PowerUpClass {
	#Public properties
	[string]$sourcePath
	[string]$PackagePath

	#Hidden properties
	hidden [string]$Hash
	
	#Constructors
	PowerUpFile ([string]$sourcePath, [string]$packagePath) {
		if (!(Test-Path $sourcePath)) {
			$this.ThrowArgumentException("Path not found: $sourcePath")
		}
		if (!$packagePath) {
			$this.ThrowArgumentException('Path inside the package cannot be empty')
		}
		$this.sourcePath = $sourcePath
		$this.packagePath = $packagePath
		$this.Hash = (Get-FileHash $sourcePath).Hash
	}

	hidden PowerUpFile ([psobject]$object) {
		if (!$object.packagePath) {
			$this.ThrowArgumentException('Path inside the package cannot be empty')
		}
		$this.sourcePath = $object.sourcePath
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