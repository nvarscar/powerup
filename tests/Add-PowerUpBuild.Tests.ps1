$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = if ($PSScriptRoot) { $PSScriptRoot } else {	(Get-Item . ).FullName }
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

. "$here\..\internal\Get-ArchiveItem.ps1"
. "$here\..\internal\New-TempWorkspaceFolder.ps1"
. "$here\..\internal\Remove-ArchiveItem.ps1"

$workFolder = New-TempWorkspaceFolder
$unpackedFolder = New-TempWorkspaceFolder

$scriptFolder = "$here\etc\install-tests\success"
$v1scripts = Join-Path $scriptFolder '1.sql'
$v2scripts = Join-Path $scriptFolder '2.sql'
$packageName = Join-Path $workFolder 'TempDeployment.zip'
$packageNameTest = "$packageName.test.zip"
$packageNoPkgFile = Join-Path $workFolder "pkg_nopkgfile.zip"

Describe "$commandName tests" {
	BeforeAll {
		$null = New-PowerUpPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force
	}
	AfterAll {
		if ($workFolder.Name -like 'PowerUpWorkspace*') { Remove-Item $workFolder -Recurse }
		if ($unpackedFolder.Name -like 'PowerUpWorkspace*') { Remove-Item $unpackedFolder -Recurse }
	}
	Context "adding version 2.0 to existing package" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
		}
		AfterAll {
			$null = Remove-Item $packageNameTest
		}
		It "should add new build to existing package" {
			$results = Add-PowerUpBuild -ScriptPath $v2scripts -Name $packageNameTest -Build 2.0
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packageNameTest -Leaf)
			Test-Path $packageNameTest | Should Be $true
		}
		$results = Get-ArchiveItem $packageNameTest
		It "build 1.0 should only contain scripts from 1.0" {
			'content\1.0\1.sql' | Should BeIn $results.Path
			'content\1.0\2.sql' | Should Not BeIn $results.Path
		}
		It "build 2.0 should only contain scripts from 2.0" {
			'content\2.0\2.sql' | Should BeIn $results.Path
			'content\2.0\1.sql' | Should Not BeIn $results.Path
		}
		It "should contain module files" {
			'Modules\PowerUp\PowerUp.psd1' | Should BeIn $results.Path
			'Modules\PowerUp\bin\DbUp.dll' | Should BeIn $results.Path
		}
		It "should contain config files" {
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
		}
	}
	Context "adding new files only based on source path (Type = New)" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
		}
		AfterAll {
			$null = Remove-Item $packageNameTest
		}
		It "should add new build to existing package" {
			$results = Add-PowerUpBuild -ScriptPath $scriptFolder -Name $packageNameTest -Build 2.0 -Type 'New'
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packageNameTest -Leaf)
			$results.Config | Should Not Be $null
			$results.Version | Should Be '2.0'
			$results.ModuleVersion | Should Be (Get-Module PowerUp).Version
			$results.Builds | Where-Object Build -eq '1.0' | Should Not Be $null
			$results.Builds | Where-Object Build -eq '2.0' | Should Not Be $null
			$results.Path | Should Be $packageNameTest
			$results.Size -gt 0 | Should Be $true
			Test-Path $packageNameTest | Should Be $true
		}
		$results = Get-ArchiveItem $packageNameTest
		It "build 1.0 should only contain scripts from 1.0" {
			'content\1.0\1.sql' | Should BeIn $results.Path
			'content\1.0\2.sql' | Should Not BeIn $results.Path
		}
		It "build 2.0 should only contain scripts from 2.0" {
			"content\2.0\$(Split-Path $scriptFolder -Leaf)\2.sql" | Should BeIn $results.Path
			"content\2.0\$(Split-Path $scriptFolder -Leaf)\1.sql" | Should Not BeIn $results.Path
		}
		It "should contain module files" {
			'Modules\PowerUp\PowerUp.psd1' | Should BeIn $results.Path
			'Modules\PowerUp\bin\DbUp.dll' | Should BeIn $results.Path
		}
		It "should contain config files" {
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
		}
	}
	Context "adding new files only based on hash (Type = Unique/Modified)" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
			$null = Copy-Item $v1scripts "$workFolder\Test.sql"
		}
		AfterAll {
			$null = Remove-Item $packageNameTest
			$null = Remove-Item "$workFolder\Test.sql"
		}
		It "should add new build to existing package" {
			$results = Add-PowerUpBuild -ScriptPath $scriptFolder, "$workFolder\Test.sql" -Name $packageNameTest -Build 2.0 -Type 'Unique'
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packageNameTest -Leaf)
			$results.Config | Should Not Be $null
			$results.Version | Should Be '2.0'
			$results.ModuleVersion | Should Be (Get-Module PowerUp).Version
			'1.0' | Should BeIn $results.Builds.Build
			'2.0' | Should BeIn $results.Builds.Build
			$results.Path | Should Be $packageNameTest
			$results.Size -gt 0 | Should Be $true
			Test-Path $packageNameTest | Should Be $true
		}
		It "should add new build to existing package based on changes in the file" {
			$null = Add-PowerUpBuild -ScriptPath "$workFolder\Test.sql" -Name $packageNameTest -Build 2.1
			"nope" | Out-File "$workFolder\Test.sql" -Append
			$results = Add-PowerUpBuild -ScriptPath $scriptFolder, "$workFolder\Test.sql" -Name $packageNameTest -Build 3.0 -Type 'Modified'
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packageNameTest -Leaf)
			$results.Config | Should Not Be $null
			$results.Version | Should Be '3.0'
			$results.ModuleVersion | Should Be (Get-Module PowerUp).Version
			'1.0' | Should BeIn $results.Builds.Build
			'2.0' | Should BeIn $results.Builds.Build
			'2.1' | Should BeIn $results.Builds.Build
			'3.0' | Should BeIn $results.Builds.Build
			$results.Path | Should Be $packageNameTest
			$results.Size -gt 0 | Should Be $true
			Test-Path $packageNameTest | Should Be $true
		}
		$results = Get-ArchiveItem $packageNameTest
		It "build 1.0 should only contain scripts from 1.0" {
			'content\1.0\1.sql' | Should BeIn $results.Path
			'content\1.0\2.sql' | Should Not BeIn $results.Path
		}
		It "build 2.0 should only contain scripts from 2.0" {
			"content\2.0\$(Split-Path $scriptFolder -Leaf)\2.sql" | Should BeIn $results.Path
			"content\2.0\$(Split-Path $scriptFolder -Leaf)\1.sql" | Should Not BeIn $results.Path
			'content\2.0\Test.sql' | Should Not BeIn $results.Path
		}
		It "build 3.0 should only contain scripts from 3.0" {
			'content\3.0\Test.sql' | Should BeIn $results.Path
			"content\3.0\$(Split-Path $scriptFolder -Leaf)\2.sql" | Should Not BeIn $results.Path
			"content\3.0\$(Split-Path $scriptFolder -Leaf)\1.sql" | Should Not BeIn $results.Path
		}
		It "should contain module files" {
			'Modules\PowerUp\PowerUp.psd1' | Should BeIn $results.Path
			'Modules\PowerUp\bin\DbUp.dll' | Should BeIn $results.Path
		}
		It "should contain config files" {
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
		}
	}
	Context "unpacked package tests" {
		BeforeAll {
			$null = New-PowerUpPackage -Name $packageNameTest -Build 1.0 -ScriptPath $scriptFolder
			Expand-Archive $packageNameTest $unpackedFolder
		}
		AfterAll {
			Remove-Item -Path (Join-Path $unpackedFolder *) -Recurse
			Remove-Item $packageNameTest
		}
		It "Should add a build to unpacked folder" {
			$results = Add-PowerUpBuild -ScriptPath "$scriptFolder\*" -Name $unpackedFolder -Unpacked -Build 2.0
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $unpackedFolder -Leaf)
			$results.Config | Should Not Be $null
			$results.Version | Should Be '2.0'
			$results.ModuleVersion | Should Be (Get-Module PowerUp).Version
			'1.0' | Should BeIn $results.Builds.Build
			'2.0' | Should BeIn $results.Builds.Build
			$results.Path | Should Be $unpackedFolder.FullName
			$results.Size | Should Be 0
			Test-Path "$unpackedFolder\content\2.0" | Should Be $true
			Get-ChildItem "$scriptFolder" | ForEach-Object {
				Test-Path "$unpackedFolder\content\2.0\$($_.Name)" | Should Be $true
			}
		}
		It "should contain module files" {
			Test-Path "$unpackedFolder\Modules\PowerUp\PowerUp.psd1" | Should Be $true
			Test-Path "$unpackedFolder\Modules\PowerUp\bin\DbUp.dll" | Should Be $true
		}
		It "should contain config files" {
			Test-Path "$unpackedFolder\PowerUp.config.json" | Should Be $true
			Test-Path "$unpackedFolder\PowerUp.package.json" | Should Be $true
		}
	}
	Context "negative tests" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
			$null = New-PowerUpPackage -Name $packageNoPkgFile -Build 1.0 -ScriptPath $scriptFolder
			$null = Remove-ArchiveItem -Path $packageNoPkgFile -Item 'PowerUp.package.json'
		}
		AfterAll {
			Remove-Item $packageNameTest
			Remove-Item $packageNoPkgFile
		}
		It "should show warning when there are no new files" {
			$result = Add-PowerUpBuild -Name $packageNameTest -ScriptPath $v1scripts -Type 'Unique' -WarningVariable warningResult 3>$null
			$warningResult.Message -join ';' | Should BeLike '*No scripts have been selected, the original file is unchanged.*'
		}
		It "should throw error when package data file does not exist" {
			try {
				$result = Add-PowerUpBuild -Name $packageNoPkgFile -ScriptPath $v2scripts -SkipValidation
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*Package file * not found*'
		}
		It "should throw error when package zip does not exist" {
			try {
				$result = Add-PowerUpBuild -Name ".\nonexistingpackage.zip" -ScriptPath $v1scripts
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*Package * not found. Aborting build*'
		}
		It "should throw error when path cannot be resolved" {
			try {
				$result = Add-PowerUpBuild -Name $packageNameTest -ScriptPath ".\nonexistingsourcefiles.sql"
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*The following path is not valid*'
		}
		It "should throw error when scripts with the same relative path is being added" {
			try {
				$result = Add-PowerUpBuild -Name $packageNameTest -ScriptPath "$scriptFolder\*", "$scriptFolder\..\transactional-failure\*"
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*already exists inside this build*'
		}
	}
}
