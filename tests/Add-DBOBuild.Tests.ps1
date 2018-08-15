﻿Param (
	[switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
	# Is not a part of the global batch => import module
	#Explicitly import the module for testing
	Import-Module "$here\..\dbops.psd1" -Force
}
else {
	# Is a part of a batch, output some eye-catching happiness
	Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

$workFolder = Join-Path "$here\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-Path $workFolder 'unpacked'

$scriptFolder = "$here\etc\install-tests\success"
$v1scripts = Join-Path $scriptFolder '1.sql'
$v2scripts = Join-Path $scriptFolder '2.sql'
$packageName = Join-Path $workFolder 'TempDeployment.zip'
$packageNameTest = "$packageName.test.zip"
$packageNoPkgFile = Join-Path $workFolder "pkg_nopkgfile.zip"

Describe "Add-DBOBuild tests" -Tag $commandName, UnitTests {
	BeforeAll {
		$null = New-Item $workFolder -ItemType Directory -Force
		$null = New-Item $unpackedFolder -ItemType Directory -Force
		$null = New-DBOPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force
	}
	AfterAll {
		if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
	}
	Context "adding version 2.0 to existing package" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
		}
		AfterAll {
			$null = Remove-Item $packageNameTest
		}
		It "should add new build to existing package" {
			$results = Add-DBOBuild -ScriptPath $v2scripts -Name $packageNameTest -Build 2.0
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
			'Modules\dbops\dbops.psd1' | Should BeIn $results.Path
			'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $results.Path
            'Modules\dbops\bin\dbup-core.dll' | Should BeIn $results.Path
		}
		It "should contain config files" {
			'dbops.config.json' | Should BeIn $results.Path
			'dbops.package.json' | Should BeIn $results.Path
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
			$results = Add-DBOBuild -ScriptPath $scriptFolder -Name $packageNameTest -Build 2.0 -Type 'New'
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packageNameTest -Leaf)
			$results.Configuration | Should Not Be $null
			$results.Version | Should Be '2.0'
			$results.ModuleVersion | Should Be (Get-Module dbops).Version
			$results.Builds | Where-Object Build -eq '1.0' | Should Not Be $null
			$results.Builds | Where-Object Build -eq '2.0' | Should Not Be $null
			$results.FullName | Should Be $packageNameTest
			$results.Length -gt 0 | Should Be $true
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
			'Modules\dbops\dbops.psd1' | Should BeIn $results.Path
			'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $results.Path
			'Modules\dbops\bin\dbup-core.dll' | Should BeIn $results.Path
		}
		It "should contain config files" {
			'dbops.config.json' | Should BeIn $results.Path
			'dbops.package.json' | Should BeIn $results.Path
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
			$results = Add-DBOBuild -ScriptPath $scriptFolder, "$workFolder\Test.sql" -Name $packageNameTest -Build 2.0 -Type 'Unique'
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packageNameTest -Leaf)
			$results.Configuration | Should Not Be $null
			$results.Version | Should Be '2.0'
			$results.ModuleVersion | Should Be (Get-Module dbops).Version
			'1.0' | Should BeIn $results.Builds.Build
			'2.0' | Should BeIn $results.Builds.Build
			$results.FullName | Should Be $packageNameTest
			$results.Length -gt 0 | Should Be $true
			Test-Path $packageNameTest | Should Be $true
		}
		It "should add new build to existing package based on changes in the file" {
			$null = Add-DBOBuild -ScriptPath "$workFolder\Test.sql" -Name $packageNameTest -Build 2.1
			"nope" | Out-File "$workFolder\Test.sql" -Append
			$results = Add-DBOBuild -ScriptPath $scriptFolder, "$workFolder\Test.sql" -Name $packageNameTest -Build 3.0 -Type 'Modified'
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packageNameTest -Leaf)
			$results.Configuration | Should Not Be $null
			$results.Version | Should Be '3.0'
			$results.ModuleVersion | Should Be (Get-Module dbops).Version
			'1.0' | Should BeIn $results.Builds.Build
			'2.0' | Should BeIn $results.Builds.Build
			'2.1' | Should BeIn $results.Builds.Build
			'3.0' | Should BeIn $results.Builds.Build
			$results.FullName | Should Be $packageNameTest
			$results.Length -gt 0 | Should Be $true
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
			'Modules\dbops\dbops.psd1' | Should BeIn $results.Path
			'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $results.Path
            'Modules\dbops\bin\dbup-core.dll' | Should BeIn $results.Path
		}
		It "should contain config files" {
			'dbops.config.json' | Should BeIn $results.Path
			'dbops.package.json' | Should BeIn $results.Path
		}
	}
	Context "negative tests" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
			$null = New-DBOPackage -Name $packageNoPkgFile -Build 1.0 -ScriptPath $scriptFolder
			$null = Remove-ArchiveItem -Path $packageNoPkgFile -Item 'dbops.package.json'
		}
		AfterAll {
			Remove-Item $packageNameTest
			Remove-Item $packageNoPkgFile
		}
		It "should show warning when there are no new files" {
			$null= Add-DBOBuild -Name $packageNameTest -ScriptPath $v1scripts -Type 'Unique' -WarningVariable warningResult 3>$null
			$warningResult.Message -join ';' | Should BeLike '*No scripts have been selected, the original file is unchanged.*'
		}
		It "should throw error when package data file does not exist" {
			try {
				$null = Add-DBOBuild -Name $packageNoPkgFile -ScriptPath $v2scripts
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*Incorrect package format*'
		}
		It "should throw error when package zip does not exist" {
			{ Add-DBOBuild -Name ".\nonexistingpackage.zip" -ScriptPath $v1scripts -ErrorAction Stop} | Should Throw
		}
		It "should throw error when path cannot be resolved" {
			try {
				$null = Add-DBOBuild -Name $packageNameTest -ScriptPath ".\nonexistingsourcefiles.sql"
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*The following path is not valid*'
		}
		It "should throw error when scripts with the same relative path is being added" {
			try {
				$null = Add-DBOBuild -Name $packageNameTest -ScriptPath "$scriptFolder\*", "$scriptFolder\..\transactional-failure\*"
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*File * already exists in*'
		}
	}
}
