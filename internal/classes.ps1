class PowerUpPackage {
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
		return [PowerUpPackage]::new((Get-Content $path -Raw -ErrorAction Stop))
	}

	#Methods
	[PowerUpBuild] NewBuild ([string]$build) {
		if (!$build) {
			Write-Error 'Build name is not specified.'
			return $null
		}
		if ($currentBuild = $this.builds | Where-Object { $_.build -eq $build }) {
			Write-Error 'Build $build already exists.'
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
			Write-Error 'Build not found.'
			return $null
		}
	}
	[void] AddBuild ([PowerUpBuild]$build) {
		if ($currentBuild = $this.builds | Where-Object { $_.build -eq $build.build }) {
			Write-Error 'Build $build already exists.'
		}
		else {
			$this.builds += $build
		}
	}
	[void] SaveToFile ([string]$fileName) {
		$this | ConvertTo-Json -Depth 5 | Out-File $fileName
	}
	[void] SaveToFile ([string]$fileName, [bool]$force) {
		$this | ConvertTo-Json -Depth 5 | Out-File $fileName -Force
	}
}
class PowerUpBuild {
	#Public properties
	[string]$build
	[PowerUpFile[]]$Scripts
	[string]$CreatedDate
	
	#Constructors
	PowerUpBuild ([string]$build) {
		if (!$build) {
			throw 'Build name cannot be empty';
		}
		$this.build = $build
		$this.CreatedDate = (Get-Date).Datetime
		#$this.deployOrder = $parent.GetLastBuildDeployOrder() + 10
	}

	hidden PowerUpBuild ([psobject]$object) {
		if (!$object.build) {
			throw 'Build name cannot be empty';
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
				throw "Script $p already exists."
			}
			else {
				$packagePath = (($p -replace '\:', '\') -replace '\\\\', '\') -replace '^\.\\', ''
				$this.scripts += New-Object PowerUpFile ($p, "$($this.build)\$packagePath")
			}
		}
	}
	[void] NewScript ([string]$fileName, [string]$relativePath) {
		if ($currentFile = $this.scripts | Where-Object { $_.sourcePath -eq $fileName }) {
			throw "Script $fileName already exists."
		}
		else {
			$packagePath = $fileName.Replace($relativePath, '').TrimStart('\').Replace('\:', '\').Replace('\\', '\') -replace '^\.\\', ''
			$this.scripts += New-Object PowerUpFile ($fileName, "$($this.build)\$packagePath")
		}
	}
	[void] AddScript ([PowerUpFile[]]$script) {
		foreach ($s in $script) {
			if ($this.scripts | Where-Object { $_.sourcePath -eq $s.sourcePath }) {
				throw "External script $($s.sourcePath) already exists."
			}
			elseif ($this.scripts | Where-Object { $_.packagePath -eq $s.packagePath }) {
				throw "Script $($s.packagePath) already exists inside this build."
			}
			else {
				$this.scripts += $script
			}
		}
	}
	[string] ToString() {
		return "[Build $($this.build)]"
	}
}

class PowerUpFile {
	#Public properties
	[string]$sourcePath
	[string]$PackagePath

	#Hidden properties
	hidden [string]$Hash
	
	#Constructors
	PowerUpFile ([string]$sourcePath, [string]$packagePath) {
		if (!(Test-Path $sourcePath)) {
			throw "Path not found: $sourcePath"
		}
		if (!$packagePath) {
			throw 'Path inside the package cannot be empty';
		}
		$this.sourcePath = $sourcePath
		$this.packagePath = $packagePath
		$this.Hash = (Get-FileHash $sourcePath).Hash
	}

	hidden PowerUpFile ([psobject]$object) {
		if (!$object.packagePath) {
			throw 'Path inside the package cannot be empty';
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