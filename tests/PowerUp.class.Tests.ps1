$here = if ($PSScriptRoot) { $PSScriptRoot } else {	(Get-Item . ).FullName }
$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. "$here\..\internal\classes\PowerUpHelper.class.ps1"
. "$here\..\internal\classes\PowerUp.class.ps1"
. "$here\..\internal\Get-ArchiveItem.ps1"
$packageName = "$here\etc\$commandName.zip"
$script:pkg = $script:build = $script:file = $null
$script1 = "$here\etc\install-tests\success\1.sql"
$script2 = "$here\etc\install-tests\success\2.sql"

Describe "$commandName - PowerUpPackage tests" -Tag $commandName, UnitTests, PowerUpPackage {
	AfterAll {
		if (Test-Path $packageName) { Remove-Item $packageName }
	}
	Context "validating PowerUpPackage creation" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		It "Should create new PowerUpPackage object" {
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.ScriptDirectory | Should Be 'content'
			$script:pkg.DeployFile.ToString() | Should Be 'Deploy.ps1'
			$script:pkg.DeployFile.GetContent() | Should BeLike '*Invoke-PowerUpDeployment @params*'
			$script:pkg.Configuration.SchemaVersionTable | Should Be 'dbo.SchemaVersions'
			$script:pkg.FileName | Should BeNullOrEmpty
			$script:pkg.$Version | Should BeNullOrEmpty
		}
		It "should save package to file" {
			{ $script:pkg.SaveToFile($packageName, $true) } | Should Not Throw
		}
		$results = Get-ArchiveItem $packageName
		It "should contain module files" {
			foreach ($file in (Get-PowerUpModuleFileList)) {
				Join-Path 'Modules\PowerUp' $file.Path | Should BeIn $results.Path
			}
		}
		It "should contain config files" {
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
		}
		It "should contain deploy file" {
			'Deploy.ps1' | Should BeIn $results.Path
		}
	}
	Context "validate PowerUpPackage being loaded from file" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.SaveToFile($packageName)
		}
		It "should load package from file" {
			$script:pkg = [PowerUpPackage]::new($packageName)
			$script:pkg.ScriptDirectory | Should Be 'content'
			$script:pkg.DeployFile.ToString() | Should Be 'Deploy.ps1'
			$script:pkg.DeployFile.GetContent() | Should BeLike '*Invoke-PowerUpDeployment @params*'
			$script:pkg.ConfigurationFile.ToString() | Should Be 'PowerUp.config.json'
			($script:pkg.ConfigurationFile.GetContent() | ConvertFrom-Json).SchemaVersionTable | Should Be 'dbo.SchemaVersions'
			$script:pkg.Configuration.SchemaVersionTable | Should Be 'dbo.SchemaVersions'
			$script:pkg.FileName | Should Be $packageName
			$script:pkg.$Version | Should BeNullOrEmpty
		}
	}
	Context "should validate PowerUpPackage methods" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.SaveToFile($packageName)
		}
		It "Should test GetBuilds method" {
			$script:pkg.GetBuilds() | Should Be $null
		}
		It "Should test NewBuild method" {
			$b = $script:pkg.NewBuild('1.0')
			$b.Build | Should Be '1.0'
			$b.PackagePath | Should Be '1.0'
			$b.Parent.GetType().Name | Should Be 'PowerUpPackage'
			$b.Scripts | Should BeNullOrEmpty
			([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
			$script:pkg.Version | Should Be '1.0'
		}
		It "Should test GetBuild method" {
			$b = $script:pkg.GetBuild('1.0')
			$b.Build | Should Be '1.0'
			$b.PackagePath | Should Be '1.0'
			$b.Parent.GetType().Name | Should Be 'PowerUpPackage'
			$b.Scripts | Should BeNullOrEmpty
			([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
		}
		It "Should test AddBuild method" {
			$script:pkg.AddBuild('2.0')
			$b = $script:pkg.GetBuild('2.0')
			$b.Build | Should Be '2.0'
			$b.PackagePath | Should Be '2.0'
			$b.Parent.GetType().Name | Should Be 'PowerUpPackage'
			$b.Scripts | Should BeNullOrEmpty
			([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
			$script:pkg.Version | Should Be '2.0'
		}
		It "Should test EnumBuilds method" {
			$script:pkg.EnumBuilds() | Should Be @('1.0', '2.0')
		}
		It "Should test GetVersion method" {
			$script:pkg.GetVersion() | Should Be '2.0'
		}
		It "Should test RemoveBuild method" {
			$script:pkg.RemoveBuild('2.0')
			'2.0' | Should Not BeIn $script:pkg.EnumBuilds()
			$script:pkg.GetBuild('2.0') | Should BeNullOrEmpty
			$script:pkg.Version | Should Be '1.0'
			#Testing overloads
			$b = $script:pkg.NewBuild('2.0')
			'2.0' | Should BeIn $script:pkg.EnumBuilds()
			$script:pkg.Version | Should Be '2.0'
			$script:pkg.RemoveBuild($b)
			'2.0' | Should Not BeIn $script:pkg.EnumBuilds()
			$script:pkg.GetBuild('2.0') | Should BeNullOrEmpty
			$script:pkg.Version | Should Be '1.0'
		}
		It "should test ScriptExists method" {
			$b = $script:pkg.GetBuild('1.0')
			$s = "$here\etc\install-tests\success\1.sql"
			$f = [PowerUpScriptFile]::new(@{SourcePath = $s; PackagePath = 'success\1.sql'})
			$f.SetContent([PowerUpHelper]::GetBinaryFile($s))
			$b.AddFile($f, 'Scripts')
			$script:pkg.ScriptExists($s) | Should Be $true
            $script:pkg.ScriptExists("$here\etc\install-tests\transactional-failure\1.sql") | Should Be $false
            { $script:pkg.ScriptExists("Nonexisting\path") } | Should Throw
		}
		It "should test ScriptModified method" {
			$s1 = "$here\etc\install-tests\success\1.sql"
			$s2 = "$here\etc\install-tests\success\2.sql"
			$script:pkg.ScriptModified($s2, $s1) | Should Be $true
			$script:pkg.ScriptModified($s1, $s1) | Should Be $false
		}
		It "should test SourcePathExists method" {
			$s1 = "$here\etc\install-tests\success\1.sql"
			$s2 = "$here\etc\install-tests\success\2.sql"
			$script:pkg.SourcePathExists($s1) | Should Be $true
			$script:pkg.SourcePathExists($s2) | Should Be $false
		}
		It "should test ExportToJson method" {
			$j = $script:pkg.ExportToJson() | ConvertFrom-Json
			$j.Builds | Should Not BeNullOrEmpty
			$j.ConfigurationFile | Should Not BeNullOrEmpty
			$j.DeployFile | Should Not BeNullOrEmpty
			$j.ScriptDirectory | Should Not BeNullOrEmpty
		}
		It "Should test GetPackagePath method" {
			$script:pkg.GetPackagePath() | Should Be 'content'
		}
		It "Should test RefreshModuleVersion method" {
			$script:pkg.RefreshModuleVersion()
			$script:pkg.ModuleVersion | Should Be (Get-Module PowerUp).Version
		}
		It "Should test RefreshFileProperties method" {
			$script:pkg.RefreshFileProperties()
			$FileObject = Get-Item $packageName
			$script:pkg.PSPath | Should Be $FileObject.PSPath.ToString()
			$script:pkg.PSParentPath | Should Be $FileObject.PSParentPath.ToString()
			$script:pkg.PSChildName | Should Be $FileObject.PSChildName.ToString()
			$script:pkg.PSDrive | Should Be $FileObject.PSDrive.ToString()
			$script:pkg.PSIsContainer | Should Be $FileObject.PSIsContainer
			$script:pkg.Mode | Should Be $FileObject.Mode
			$script:pkg.BaseName | Should Be $FileObject.BaseName
			$script:pkg.Name | Should Be $FileObject.Name
			$script:pkg.Length | Should Be $FileObject.Length
			$script:pkg.DirectoryName | Should Be $FileObject.DirectoryName
			$script:pkg.Directory | Should Be $FileObject.Directory.ToString()
			$script:pkg.IsReadOnly | Should Be $FileObject.IsReadOnly
			$script:pkg.Exists | Should Be $FileObject.Exists
			$script:pkg.FullName | Should Be $FileObject.FullName
			$script:pkg.Extension | Should Be $FileObject.Extension
			$script:pkg.CreationTime | Should Be $FileObject.CreationTime
			$script:pkg.CreationTimeUtc | Should Be $FileObject.CreationTimeUtc
			$script:pkg.LastAccessTime | Should Be $FileObject.LastAccessTime
			$script:pkg.LastAccessTimeUtc | Should Be $FileObject.LastAccessTimeUtc
			$script:pkg.LastWriteTime | Should Be $FileObject.LastWriteTime
			$script:pkg.LastWriteTimeUtc | Should Be $FileObject.LastWriteTimeUtc
			$script:pkg.Attributes | Should Be $FileObject.Attributes
		}

		It "Should test SetConfiguration method" {
			$config = @{ SchemaVersionTable = 'dbo.NewTable' } | ConvertTo-Json -Depth 1
			{ $script:pkg.SetConfiguration([PowerUpConfig]::new($config)) } | Should Not Throw
			$script:pkg.Configuration.SchemaVersionTable | Should Be 'dbo.NewTable'
		}
		$oldResults = Get-ArchiveItem $packageName | ? IsFolder -eq $false
		#Sleep 1 second to ensure that modification date is changed
		Start-Sleep -Seconds 2
		It "should test Save*/Alter methods" {
			{ $script:pkg.SaveToFile($packageName) } | Should Throw
			{ $script:pkg.Alter() } | Should Not Throw
			$results = Get-ArchiveItem $packageName
			foreach ($file in (Get-PowerUpModuleFileList)) {
				Join-Path 'Modules\PowerUp' $file.Path | Should BeIn $results.Path
			}
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
			'Deploy.ps1' | Should BeIn $results.Path
			'content\1.0\success\1.sql' | Should BeIn $results.Path
		}
		# Testing file contents to be updated by the Save method
		$results = Get-ArchiveItem $packageName | ? IsFolder -eq $false
		$saveTestsErrors = 0
		foreach ($result in $oldResults) {
			if ($result.ModifyDate -ge ($results | ? Path -eq $result.Path).ModifyDate) {
				It "Should have updated Modified date for file $($result.Path)" {
					$result.ModifyDate -lt ($results | ? Path -eq $result.Path).ModifyDate | Should Be $true
				}
				$saveTestsErrors++
			}
		}
		if ($saveTestsErrors -eq 0) {
			It "Ran silently $($oldResults.Length) file modification tests" {
				$saveTestsErrors | Should be 0
			}
		}
		It "Should test static GetDeployFile method" {
			$f = [PowerUpPackage]::GetDeployFile()
			$f.Type | Should Be 'Misc'
			$f.Path | Should BeLike '*\Deploy.ps1'
			$f.Name | Should Be 'Deploy.ps1'
		}
	}
}

Describe "$commandName - PowerUpBuild tests" -Tag $commandName, UnitTests, PowerUpBuild {
	Context "tests PowerUpBuild object creation" {
		It "Should create new PowerUpBuild object" {
			$b = [PowerUpBuild]::new('1.0')
			$b.Build | Should Be '1.0'
			$b.PackagePath | Should Be '1.0'
			([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
		}
		It "Should create new PowerUpBuild object using custom object" {
			$obj = @{
				Build       = '2.0'
				PackagePath = '2.00'
				CreatedDate = (Get-Date).Date
			}
			$b = [PowerUpBuild]::new($obj)
			$b.Build | Should Be $obj.Build
			$b.PackagePath | Should Be $obj.PackagePath
			$b.CreatedDate | Should Be $obj.CreatedDate
		}
    }
    Context "tests PowerUpBuild file adding methods" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.SaveToFile($packageName)
		}
		BeforeEach {
			if ( $script:pkg.GetBuild('1.0')) { $script:pkg.RemoveBuild('1.0') }
			$b = $script:pkg.NewBuild('1.0')
			# $f = [PowerUpFile]::new($script1, 'success\1.sql')
			# $b.AddScript($f)
			$script:build = $b
		}
		It "should test NewScript([psobject]) method" {
			$so = $script:build.NewScript(@{FullName = $script1; Depth = 1})
			#test build to contain the script
			'1.sql' | Should BeIn $script:build.Scripts.Name
			($script:build.Scripts | Measure-Object).Count | Should Be 1
			#test the file returned to have all the necessary properties
			$so.SourcePath | Should Be $script1
			$so.PackagePath | Should Be 'success\1.sql'
			$so.Length -gt 0 | Should Be $true
			$so.Name | Should Be '1.sql'
			$so.LastWriteTime | Should Not BeNullOrEmpty
			$so.ByteArray | Should Not BeNullOrEmpty
			$so.Hash |Should Not BeNullOrEmpty
			$so.Parent.ToString() | Should Be '[Build: 1.0; Scripts: @{1.sql}]'  
		}
		It "should test NewScript([string],[int]) method" {
			$so = $script:build.NewScript(@{FullName = $script1; Depth = 1})
			($script:build.Scripts | Measure-Object).Count | Should Be 1
			$so.SourcePath | Should Be $script1
			$so.PackagePath | Should Be 'success\1.sql'
			$so.Length -gt 0 | Should Be $true
			$so.Name | Should Be '1.sql'
			$so.LastWriteTime | Should Not BeNullOrEmpty
			$so.ByteArray | Should Not BeNullOrEmpty
			$so.Hash |Should Not BeNullOrEmpty
			$so.Parent.ToString() | Should Be '[Build: 1.0; Scripts: @{1.sql}]'  
			{ $script:pkg.Alter() } | Should Not Throw
			#Negative tests
			{ $script:build.NewScript($script1, 1) } | Should Throw
        }
		It "Should test AddScript([string]) method" {
			$f = [PowerUpFile]::new($script1, 'success\1.sql')
			$script:build.AddScript($f)
			#test build to contain the script
			'1.sql' | Should BeIn $script:build.Scripts.Name
			($script:build.Scripts | Measure-Object).Count | Should Be 1
		}
		It "Should test AddScript([string],[bool]) method" {
			$f = [PowerUpFile]::new($script1, 'success\1.sql')
			$script:build.AddScript($f,$false)
			#test build to contain the script
			'1.sql' | Should BeIn $script:build.Scripts.Name
			($script:build.Scripts | Measure-Object).Count | Should Be 1
			$f2 = [PowerUpFile]::new($script1, 'success\1a.sql')
			{ $script:build.AddScript($f2, $false) } | Should Throw
			($script:build.Scripts | Measure-Object).Count | Should Be 1
			$f3 = [PowerUpFile]::new($script1, 'success\1a.sql')
			$script:build.AddScript($f3, $true)
			($script:build.Scripts | Measure-Object).Count | Should Be 2
		}
	}
	Context "tests other methods" {
		BeforeEach {
			if ( $script:pkg.GetBuild('1.0')) { $script:pkg.RemoveBuild('1.0') }
			$b = $script:pkg.NewBuild('1.0')
			$f = [PowerUpScriptFile]::new($script1, 'success\1.sql')
			$b.AddScript($f)
			$script:build = $b
		}
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.SaveToFile($packageName)
		}
        It "should test ToString method" {
            $script:build.ToString() | Should Be '[Build: 1.0; Scripts: @{1.sql}]'  
        }
        It "should test HashExists method" {
            $f = [PowerUpScriptFile]::new(@{PackagePath = '1.sql'; SourcePath = '.\1.sql'; Hash = 'MyHash'})
            $script:build.AddScript($f, $true)
            $script:build.HashExists('MyHash') | Should Be $true
            $script:build.HashExists('MyHash2') | Should Be $false
            $script:build.HashExists('MyHash','.\1.sql') | Should Be $true
            $script:build.HashExists('MyHash','.\1a.sql') | Should Be $false
            $script:build.HashExists('MyHash2','.\1.sql') | Should Be $false
        }
        It "should test ScriptExists method" {
			$script:build.ScriptExists($script1) | Should Be $true
            $script:build.ScriptExists("$here\etc\install-tests\transactional-failure\1.sql") | Should Be $false
            { $script:build.ScriptExists("Nonexisting\path") } | Should Throw
		}
		It "should test ScriptModified method" {
			$script:build.ScriptModified($script1, $script1) | Should Be $false
			$script:build.ScriptModified($script2, $script1) | Should Be $true
			$script:build.ScriptModified($script2, $script2) | Should Be $false
		}
		It "should test SourcePathExists method" {
			$script:build.SourcePathExists($script1) | Should Be $true
			$script:build.SourcePathExists($script2) | Should Be $false
			$script:build.SourcePathExists('') | Should Be $false
		}
		It "should test PackagePathExists method" {
			$s1 = "success\1.sql"
			$s2 = "success\2.sql"
			$script:build.PackagePathExists($s1) | Should Be $true
			$script:build.PackagePathExists($s2) | Should Be $false
			#Overloads
			$script:build.PackagePathExists("a\$s1", 1) | Should Be $true
			$script:build.PackagePathExists("a\$s2", 1) | Should Be $false
		}
		It "should test GetPackagePath method" {
			$script:build.GetPackagePath() | Should Be 'content\1.0'
		}
		It "should test ExportToJson method" {
			$j = $script:build.ExportToJson() | ConvertFrom-Json
			$j.Scripts | Should Not BeNullOrEmpty
			$j.Build | Should Be '1.0'
			$j.PackagePath | Should Be '1.0'
			$j.CreatedDate | Should Not BeNullOrEmpty
		}
		It "should test Save method" {
			#Add file to the build
			$null = $script:build.NewScript($script2, 1)
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			$stream = [FileStream]::new($packageName, $writeMode)
			try {
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
				try {
					#Initiate saving
					{ $script:build.Save($zip) } | Should Not Throw
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}
			$results = Get-ArchiveItem $packageName
			foreach ($file in (Get-PowerUpModuleFileList)) {
				Join-Path 'Modules\PowerUp' $file.Path | Should BeIn $results.Path
			}
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
			'Deploy.ps1' | Should BeIn $results.Path
			'content\1.0\success\1.sql' | Should BeIn $results.Path
			'content\1.0\success\2.sql' | Should BeIn $results.Path
		}
		$oldResults = Get-ArchiveItem $packageName | ? IsFolder -eq $false
		#Sleep 1 second to ensure that modification date is changed
		Start-Sleep -Seconds 2
		It "should test Alter method" {
			$null = $script:build.NewScript($script2, 1)
			{ $script:build.Alter() } | Should Not Throw
			$results = Get-ArchiveItem $packageName
			foreach ($file in (Get-PowerUpModuleFileList)) {
				Join-Path 'Modules\PowerUp' $file.Path | Should BeIn $results.Path
			}
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
			'Deploy.ps1' | Should BeIn $results.Path
			'content\1.0\success\1.sql' | Should BeIn $results.Path
			'content\1.0\success\2.sql' | Should BeIn $results.Path
		}
		# Testing file contents to be updated by the Save method
		$results = Get-ArchiveItem $packageName | ? IsFolder -eq $false
		$saveTestsErrors = 0
		#should trigger file updates for build files and module files
		foreach ($result in ($oldResults | ? { $_.Path -like 'content\1.0\success' -or $_.Path -like 'Modules\PowerUp\*'  } )) {
			if ($result.ModifyDate -ge ($results | ? Path -eq $result.Path).ModifyDate) {
				It "Should have updated Modified date for file $($result.Path)" {
					$result.ModifyDate -lt ($results | ? Path -eq $result.Path).ModifyDate | Should Be $true
				}
				$saveTestsErrors++
			}
		}
		if ($saveTestsErrors -eq 0) {
			It "Ran silently $($oldResults.Length) file modification tests" {
				$saveTestsErrors | Should be 0
			}
		}
    }
}
Describe "$commandName - PowerUpFile tests" -Tag $commandName, UnitTests, PowerUpFile {
	AfterAll {
		if (Test-Path $packageName) { Remove-Item $packageName }
	}
	Context "tests PowerUpFile object creation" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		It "Should create new PowerUpFile object" {
			$f = [PowerUpFile]::new()
			# $f | Should Not BeNullOrEmpty
			$f.SourcePath | Should BeNullOrEmpty
			$f.PackagePath | Should BeNullOrEmpty
			$f.Length | Should Be 0 
			$f.Name | Should BeNullOrEmpty
			$f.LastWriteTime | Should BeNullOrEmpty
			$f.ByteArray | Should BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty
		}
		It "Should create new PowerUpFile object from path" {
			$f = [PowerUpFile]::new($script1, '1.sql')
			$f | Should Not BeNullOrEmpty
			$f.SourcePath | Should Be $script1
			$f.PackagePath | Should Be '1.sql'
			$f.Length -gt 0 | Should Be $true
			$f.Name | Should Be '1.sql'
			$f.LastWriteTime | Should Not BeNullOrEmpty
			$f.ByteArray | Should Not BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty
			#Negative tests
			{ [PowerUpFile]::new('Nonexisting\path', '1.sql') } | Should Throw
			{ [PowerUpFile]::new($script1, '') } | Should Throw
			{ [PowerUpFile]::new('', '1.sql') } | Should Throw
		}
		It "Should create new PowerUpFile object using custom object" {
			$obj = @{
				SourcePath  = $script1
				packagePath = '1.sql'
				Hash        = 'MyHash'
			}
			$f = [PowerUpFile]::new($obj)
			$f | Should Not BeNullOrEmpty
			$f.SourcePath | Should Be $script1
			$f.PackagePath | Should Be '1.sql'
			$f.Length | Should Be 0
			$f.Name | Should BeNullOrEmpty
			$f.LastWriteTime | Should BeNullOrEmpty
			$f.ByteArray | Should BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty

			#Negative tests
			$obj = @{ foo = 'bar'}
			{ [PowerUpFile]::new($obj) } | Should Throw
		}
		It "Should create new PowerUpFile object from zipfile using custom object" {
			$p = [PowerUpPackage]::new()
			$null = $p.NewBuild('1.0').NewScript($script1, 1)
			$p.SaveToFile($packageName)
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			try {
				$stream = [FileStream]::new($packageName, $writeMode)
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Read)
				try {
					$zipEntry = $zip.Entries | ? FullName -eq 'content\1.0\success\1.sql'
					$obj = @{
						SourcePath  = $script1
						packagePath = '1.sql'
						Hash        = 'MyHash'
					}
					# { [PowerUpFile]::new($obj, $zipEntry) } | Should Throw #hash is invalid
					# $obj.Hash = [PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($script1)))
					$f = [PowerUpFile]::new($obj, $zipEntry)
					$f | Should Not BeNullOrEmpty
					$f.SourcePath | Should Be $script1
					$f.PackagePath | Should Be '1.sql'
					$f.Length -gt 0 | Should Be $true
					$f.Name | Should Be '1.sql'
					$f.LastWriteTime | Should Not BeNullOrEmpty
					$f.ByteArray | Should Not BeNullOrEmpty
					# $f.Hash | Should Be $obj.Hash
					$f.Hash | Should BeNullOrEmpty
					$f.Parent | Should BeNullOrEmpty
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}

			#Negative tests
			$badobj = @{ foo = 'bar'}
			{ [PowerUpFile]::new($badobj, $zip) } | Should Throw #object is incorrect
			{ [PowerUpFile]::new($obj, $zip) } | Should Throw #zip stream has been disposed
		}
	}
	Context "tests other PowerUpFile methods" {
		BeforeEach {
			if ( $script:build.GetFile('success\1.sql', 'Scripts')) { $script:build.RemoveFile('success\1.sql', 'Scripts') }
			$script:file = $script:build.NewFile($script1, 'success\1.sql', 'Scripts')
			$script:build.Alter()
		}
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:build = $script:pkg.NewBuild('1.0')
			$script:pkg.SaveToFile($packageName, $true)
		}
		It "should test ToString method" {
			$script:file.ToString() | Should Be 'success\1.sql'  
		}
		It "should test GetContent method" {
			$script:file.GetContent() | Should BeLike 'CREATE TABLE dbo.a (a int)*'
			#ToDo: add files with different encodings
		}
		It "should test SetContent method" {
			$oldData = $script:file.ByteArray
			$oldHash = $script:file.Hash
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			$script:file.ByteArray | Should Not Be $oldData
			$script:file.ByteArray | Should Not BeNullOrEmpty
			# $script:file.Hash | Should Not Be $oldHash
			# $script:file.Hash | Should Not BeNullOrEmpty
		}
		It "should test ExportToJson method" {
			$j = $script:file.ExportToJson() | ConvertFrom-Json
			$j.PackagePath | Should Be 'success\1.sql'
			# $j.Hash | Should Be ([PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($script1))))
			$j.SourcePath | Should Be $script1
		}
		It "should test Save method" {
			#Save old file parameters
			$oldResults = Get-ArchiveItem $packageName | ? Path -eq 'content\1.0\success\1.sql'
			#Sleep 2 seconds to ensure that modification date is changed
			Start-Sleep -Seconds 2
			#Modify file content
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			$stream = [FileStream]::new($packageName, $writeMode)
			try {
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
				try {
					#Initiate saving
					{ $script:file.Save($zip) } | Should Not Throw
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}
			$results = Get-ArchiveItem $packageName | ? Path -eq 'content\1.0\success\1.sql'
			$oldResults.ModifyDate -lt ($results | ? Path -eq $oldResults.Path).ModifyDate | Should Be $true
			# { $p = [PowerUpPackage]::new($packageName) } | Should Throw #Because of the hash mismatch - package file is not updated in Save()
		}
		It "should test Alter method" {
			#Save old file parameters
			$oldResults = Get-ArchiveItem $packageName | ? Path -eq 'content\1.0\success\1.sql'
			#Sleep 2 seconds to ensure that modification date is changed
			Start-Sleep -Seconds 2
			#Modify file content
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			{ $script:file.Alter() } | Should Not Throw
			$results = Get-ArchiveItem $packageName | ? Path -eq 'content\1.0\success\1.sql'
			$oldResults.ModifyDate -lt ($results | ? Path -eq $oldResults.Path).ModifyDate | Should Be $true
		}
	}
}

Describe "$commandName - PowerUpScriptFile tests" -Tag $commandName, UnitTests, PowerUpFile, PowerUpScriptFile {
	AfterAll {
		if (Test-Path $packageName) { Remove-Item $packageName }
	}
	Context "tests PowerUpScriptFile object creation" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		It "Should create new PowerUpScriptFile object" {
			$f = [PowerUpScriptFile]::new()
			# $f | Should Not BeNullOrEmpty
			$f.SourcePath | Should BeNullOrEmpty
			$f.PackagePath | Should BeNullOrEmpty
			$f.Length | Should Be 0 
			$f.Name | Should BeNullOrEmpty
			$f.LastWriteTime | Should BeNullOrEmpty
			$f.ByteArray | Should BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty
		}
		It "Should create new PowerUpScriptFile object from path" {
			$f = [PowerUpScriptFile]::new($script1, '1.sql')
			$f | Should Not BeNullOrEmpty
			$f.SourcePath | Should Be $script1
			$f.PackagePath | Should Be '1.sql'
			$f.Length -gt 0 | Should Be $true
			$f.Name | Should Be '1.sql'
			$f.LastWriteTime | Should Not BeNullOrEmpty
			$f.ByteArray | Should Not BeNullOrEmpty
			$f.Hash | Should Not BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty
			#Negative tests
			{ [PowerUpScriptFile]::new('Nonexisting\path', '1.sql') } | Should Throw
			{ [PowerUpScriptFile]::new($script1, '') } | Should Throw
			{ [PowerUpScriptFile]::new('', '1.sql') } | Should Throw
		}
		It "Should create new PowerUpScriptFile object using custom object" {
			$obj = @{
				SourcePath  = $script1
				packagePath = '1.sql'
				Hash        = 'MyHash'
			}
			$f = [PowerUpScriptFile]::new($obj)
			$f | Should Not BeNullOrEmpty
			$f.SourcePath | Should Be $script1
			$f.PackagePath | Should Be '1.sql'
			$f.Length | Should Be 0
			$f.Name | Should BeNullOrEmpty
			$f.LastWriteTime | Should BeNullOrEmpty
			$f.ByteArray | Should BeNullOrEmpty
			$f.Hash | Should Be 'MyHash'
			$f.Parent | Should BeNullOrEmpty

			#Negative tests
			$obj = @{ foo = 'bar'}
			{ [PowerUpScriptFile]::new($obj) } | Should Throw
		}
		It "Should create new PowerUpScriptFile object from zipfile using custom object" {
			$p = [PowerUpPackage]::new()
			$null = $p.NewBuild('1.0').NewScript($script1, 1)
			$p.SaveToFile($packageName)
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			try {
				$stream = [FileStream]::new($packageName, $writeMode)
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Read)
				try {
					$zipEntry = $zip.Entries | ? FullName -eq 'content\1.0\success\1.sql'
					$obj = @{
						SourcePath  = $script1
						packagePath = '1.sql'
						Hash        = 'MyHash'
					}
					{ [PowerUpScriptFile]::new($obj, $zipEntry) } | Should Throw #hash is invalid
					$obj.Hash = [PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($script1)))
					$f = [PowerUpScriptFile]::new($obj, $zipEntry)
					$f | Should Not BeNullOrEmpty
					$f.SourcePath | Should Be $script1
					$f.PackagePath | Should Be '1.sql'
					$f.Length -gt 0 | Should Be $true
					$f.Name | Should Be '1.sql'
					$f.LastWriteTime | Should Not BeNullOrEmpty
					$f.ByteArray | Should Not BeNullOrEmpty
					$f.Hash | Should Be $obj.Hash
					$f.Parent | Should BeNullOrEmpty
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}

			#Negative tests
			$badobj = @{ foo = 'bar'}
			{ [PowerUpScriptFile]::new($badobj, $zip) } | Should Throw #object is incorrect
			{ [PowerUpScriptFile]::new($obj, $zip) } | Should Throw #zip stream has been disposed
		}
	}
	Context "tests overloaded PowerUpScriptFile methods" {
		BeforeEach {
			if ( $script:build.GetFile('success\1.sql', 'Scripts')) { $script:build.RemoveFile('success\1.sql', 'Scripts') }
			$script:file = $script:build.NewFile($script1, 'success\1.sql', 'Scripts', [PowerUpScriptFile])
			$script:build.Alter()
		}
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:build = $script:pkg.NewBuild('1.0')
			$script:pkg.SaveToFile($packageName, $true)
		}
		It "should test SetContent method" {
			$oldData = $script:file.ByteArray
			$oldHash = $script:file.Hash
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			$script:file.ByteArray | Should Not Be $oldData
			$script:file.ByteArray | Should Not BeNullOrEmpty
			$script:file.Hash | Should Not Be $oldHash
			$script:file.Hash | Should Not BeNullOrEmpty
		}
		It "should test ExportToJson method" {
			$j = $script:file.ExportToJson() | ConvertFrom-Json
			$j.PackagePath | Should Be 'success\1.sql'
			$j.Hash | Should Be ([PowerUpHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([PowerUpHelper]::GetBinaryFile($script1))))
			$j.SourcePath | Should Be $script1
		}
		It "should test Save method" {
			#Save old file parameters
			$oldResults = Get-ArchiveItem $packageName | ? Path -eq 'content\1.0\success\1.sql'
			#Sleep 2 seconds to ensure that modification date is changed
			Start-Sleep -Seconds 2
			#Modify file content
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			$stream = [FileStream]::new($packageName, $writeMode)
			try {
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
				try {
					#Initiate saving
					{ $script:file.Save($zip) } | Should Not Throw
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}
			$results = Get-ArchiveItem $packageName | ? Path -eq 'content\1.0\success\1.sql'
			$oldResults.ModifyDate -lt ($results | ? Path -eq $oldResults.Path).ModifyDate | Should Be $true
			{ $p = [PowerUpPackage]::new($packageName) } | Should Throw #Because of the hash mismatch - package file is not updated in Save()
		}
		It "should test Alter method" {
			#Save old file parameters
			$oldResults = Get-ArchiveItem $packageName | ? Path -eq 'content\1.0\success\1.sql'
			#Sleep 2 seconds to ensure that modification date is changed
			Start-Sleep -Seconds 2
			#Modify file content
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			{ $script:file.Alter() } | Should Not Throw
			$results = Get-ArchiveItem $packageName | ? Path -eq 'content\1.0\success\1.sql'
			$oldResults.ModifyDate -lt ($results | ? Path -eq $oldResults.Path).ModifyDate | Should Be $true
			$p = [PowerUpPackage]::new($packageName)
			$p.Builds[0].Scripts[0].GetContent() | Should BeLike 'CREATE TABLE dbo.c (a int)*'
		}
	}
}
Describe "$commandName - PowerUpRootFile tests" -Tag $commandName, UnitTests, PowerUpFile, PowerUpRootFile {
	AfterAll {
		if (Test-Path $packageName) { Remove-Item $packageName }
	}
	Context "tests PowerUpFile object creation" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		It "Should create new PowerUpRootFile object" {
			$f = [PowerUpRootFile]::new()
			# $f | Should Not BeNullOrEmpty
			$f.SourcePath | Should BeNullOrEmpty
			$f.PackagePath | Should BeNullOrEmpty
			$f.Length | Should Be 0 
			$f.Name | Should BeNullOrEmpty
			$f.LastWriteTime | Should BeNullOrEmpty
			$f.ByteArray | Should BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty
		}
		It "Should create new PowerUpRootFile object from path" {
			$f = [PowerUpRootFile]::new($script1, '1.sql')
			$f | Should Not BeNullOrEmpty
			$f.SourcePath | Should Be $script1
			$f.PackagePath | Should Be '1.sql'
			$f.Length -gt 0 | Should Be $true
			$f.Name | Should Be '1.sql'
			$f.LastWriteTime | Should Not BeNullOrEmpty
			$f.ByteArray | Should Not BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty
			#Negative tests
			{ [PowerUpRootFile]::new('Nonexisting\path', '1.sql') } | Should Throw
			{ [PowerUpRootFile]::new($script1, '') } | Should Throw
			{ [PowerUpRootFile]::new('', '1.sql') } | Should Throw
		}
		It "Should create new PowerUpRootFile object using custom object" {
			$obj = @{
				SourcePath  = $script1
				packagePath = '1.sql'
				Hash        = 'MyHash'
			}
			$f = [PowerUpRootFile]::new($obj)
			$f | Should Not BeNullOrEmpty
			$f.SourcePath | Should Be $script1
			$f.PackagePath | Should Be '1.sql'
			$f.Length | Should Be 0
			$f.Name | Should BeNullOrEmpty
			$f.LastWriteTime | Should BeNullOrEmpty
			$f.ByteArray | Should BeNullOrEmpty
			$f.Hash | Should BeNullOrEmpty
			$f.Parent | Should BeNullOrEmpty

			#Negative tests
			$obj = @{ foo = 'bar'}
			{ [PowerUpFile]::new($obj) } | Should Throw
		}
		It "Should create new PowerUpRootFile object from zipfile using custom object" {
			$p = [PowerUpPackage]::new()
			$null = $p.NewBuild('1.0').NewScript($script1, 1)
			$p.SaveToFile($packageName)
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			try {
				$stream = [FileStream]::new($packageName, $writeMode)
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Read)
				try {
					$zipEntry = $zip.Entries | ? FullName -eq 'content\1.0\success\1.sql'
					$obj = @{
						SourcePath  = $script1
						packagePath = '1.sql'
						Hash        = 'MyHash'
					}
					$f = [PowerUpRootFile]::new($obj, $zipEntry)
					$f | Should Not BeNullOrEmpty
					$f.SourcePath | Should Be $script1
					$f.PackagePath | Should Be '1.sql'
					$f.Length -gt 0 | Should Be $true
					$f.Name | Should Be '1.sql'
					$f.LastWriteTime | Should Not BeNullOrEmpty
					$f.ByteArray | Should Not BeNullOrEmpty
					$f.Hash | Should BeNullOrEmpty
					$f.Parent | Should BeNullOrEmpty
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}

			#Negative tests
			$badobj = @{ foo = 'bar'}
			{ [PowerUpRootFile]::new($badobj, $zip) } | Should Throw #object is incorrect
			{ [PowerUpRootFile]::new($obj, $zip) } | Should Throw #zip stream has been disposed
		}
	}
	Context "tests overloaded PowerUpRootFile methods" {
		AfterAll {
			if (Test-Path $packageName) { Remove-Item $packageName }
		}
		BeforeAll {
			$script:pkg = [PowerUpPackage]::new()
			$script:pkg.SaveToFile($packageName, $true)
			$script:file = $script:pkg.GetFile('Deploy.ps1', 'DeployFile')
		}
		It "should test SetContent method" {
			$oldData = $script:file.ByteArray
			$oldHash = $script:file.Hash
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			$script:file.ByteArray | Should Not Be $oldData
			$script:file.ByteArray | Should Not BeNullOrEmpty
			$script:file.Hash | Should BeNullOrEmpty
		}
		It "should test ExportToJson method" {
			$j = $script:file.ExportToJson() | ConvertFrom-Json
			$j.PackagePath | Should Be 'Deploy.ps1'
			$j.SourcePath | Should Be (Get-PowerUpModuleFileList | Where-Object {$_.Type -eq 'Misc' -and $_.Name -eq 'Deploy.ps1'}).FullName
		}
		It "should test Save method" {
			#Save old file parameters
			$oldResults = Get-ArchiveItem $packageName | ? Path -eq 'Deploy.ps1'
			#Sleep 2 seconds to ensure that modification date is changed
			Start-Sleep -Seconds 2
			#Modify file content
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			#Open zip file stream
			$writeMode = [System.IO.FileMode]::Open
			$stream = [FileStream]::new($packageName, $writeMode)
			try {
				#Open zip file
				$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
				try {
					#Initiate saving
					{ $script:file.Save($zip) } | Should Not Throw
				}
				catch {
					throw $_
				}
				finally {
					#Close archive
					$zip.Dispose()
				}
			}
			catch {
				throw $_
			}
			finally {
				#Close archive
				$stream.Dispose()
			}
			$results = Get-ArchiveItem $packageName | ? Path -eq 'Deploy.ps1'
			$oldResults.ModifyDate -lt ($results | ? Path -eq $oldResults.Path).ModifyDate | Should Be $true
		}
		It "should test Alter method" {
			#Save old file parameters
			$oldResults = Get-ArchiveItem $packageName | ? Path -eq 'Deploy.ps1'
			#Sleep 2 seconds to ensure that modification date is changed
			Start-Sleep -Seconds 2
			#Modify file content
			$script:file.SetContent([PowerUpHelper]::GetBinaryFile($script2))
			{ $script:file.Alter() } | Should Not Throw
			$results = Get-ArchiveItem $packageName | ? Path -eq 'Deploy.ps1'
			$oldResults.ModifyDate -lt ($results | ? Path -eq $oldResults.Path).ModifyDate | Should Be $true
		}
	}
}