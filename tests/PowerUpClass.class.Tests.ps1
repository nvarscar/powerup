$here = if ($PSScriptRoot) { $PSScriptRoot } else {	(Get-Item . ).FullName }
$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. "$here\..\internal\classes\PowerUpClass.class.ps1"
. "$here\..\internal\Get-ArchiveItem.ps1"
$packageName = "$here\etc\$commandName.zip"
$script:pkg = $null

Describe "$commandName - PowerUpPackage tests" {
    AfterAll {
        if (Test-Path $packageName) { Remove-Item $packageName }
    }
	Context "validating PowerUpPackage creation" {
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
			{ $script:pkg.SaveToFile($packageName) } | Should Not Throw
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
            $script:pkg.EnumBuilds() | Should Be @('1.0','2.0')
        }
        It "Should test GetVersion method" {
            $script:pkg.GetVersion() | Should Be '2.0'
        }
        It "Should test RemoveBuild method" {
            $script:pkg.RemoveBuild('2.0')
            '2.0' | Should Not BeIn $script:pkg.EnumBuilds()
            try {
                $b = $script:pkg.GetBuild('2.0')
            }
            catch {
                $result = $_.Exception.Message -join ';'
            }
            $script:pkg.Version | Should Be '1.0'
            $result | Should BeLike '*Build not found*'
            #Testing overloads
            $b = $script:pkg.NewBuild('2.0')
            '2.0' | Should BeIn $script:pkg.EnumBuilds()
            $script:pkg.Version | Should Be '2.0'
            $script:pkg.RemoveBuild($b)
            '2.0' | Should Not BeIn $script:pkg.EnumBuilds()
            try {
                $b = $script:pkg.GetBuild('2.0')
            }
            catch {
                $result = $_.Exception.Message -join ';'
            }
            $script:pkg.Version | Should Be '1.0'
            $result | Should BeLike '*Build not found*'
        }
        It "should test ScriptExists method" {
            $b = $script:pkg.GetBuild('1.0')
            $s = "$here\etc\install-tests\success\1.sql"
            $f = [PowerUpFile]::new(@{SourcePath = $s; PackagePath = 'success\1.sql'})
            $f.SetContent($f.GetBinaryFile($s))
            $b.AddFile($f, 'Scripts')
            $script:pkg.ScriptExists($s) | Should Be $true
			$script:pkg.ScriptExists("$here\etc\install-tests\transactional-failure\1.sql") | Should Be $false
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
        It "Should test SetConfiguration method" {
            $config = @{ SchemaVersionTable = 'dbo.NewTable' } | ConvertTo-Json -Depth 1
            { $script:pkg.SetConfiguration([PowerUpConfig]::new($config)) } | Should Not Throw
            $script:pkg.Configuration.SchemaVersionTable | Should Be 'dbo.NewTable'
        }
        $oldResults = Get-ArchiveItem $packageName | ? IsFolder -eq $false
        #Sleep 1 second to ensure that modification date is changed
        Start-Sleep -Seconds 1
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
        foreach($result in $oldResults) {
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
    Context "tests PowerUpBuild object" {
        It "should test PackagePathExists method" {
            $s1 = "success\1.sql"
            $s2 = "success\2.sql"
            $script:pkg.GetBuild('1.0').PackagePathExists($s1) | Should Be $true
            $script:pkg.GetBuild('1.0').PackagePathExists($s2) | Should Be $false
            #Overloads
			$script:pkg.GetBuild('1.0').PackagePathExists("a\$s1", 1) | Should Be $true
			$script:pkg.GetBuild('1.0').PackagePathExists("a\$s2", 1) | Should Be $false
        }
        
        
        
	}

    
	
	# $p.AddBuild('1.0')
	# $b = $p.GetBuild('1.0')
	# $b.NewScript('c:\temp\a.htm', 0)
	# $b.Alter()
	# $pp = [poweruppackage]::new($fileName)
}
