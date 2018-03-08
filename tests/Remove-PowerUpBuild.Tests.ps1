Param (
	[switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
	# Is not a part of the global batch => import module
	#Explicitly import the module for testing
	Import-Module "$here\..\PowerUp.psd1" -Force
}
else {
	# Is a part of a batch, output some eye-catching happiness
	Write-Host "Running $commandName tests" -ForegroundColor Cyan
}


. "$here\..\internal\Get-ArchiveItem.ps1"
. "$here\..\internal\Remove-ArchiveItem.ps1"

$workFolder = Join-Path "$here\etc" "$commandName.Tests.PowerUp"
$unpackedFolder = Join-Path $workFolder 'unpacked'

$scriptFolder = "$here\etc\install-tests\success"
$v1scripts = Join-Path $scriptFolder "1.sql"
$v2scripts = Join-Path $scriptFolder "2.sql"
$packageName = Join-Path $workFolder "TempDeployment.zip"
$packageNameTest = "$packageName.test.zip"
$packageNoPkgFile = Join-Path $workFolder "pkg_nopkgfile.zip"

Describe "Remove-PowerUpBuild tests" -Tag $commandName, UnitTests {
	BeforeAll {
		if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.PowerUp') { Remove-Item $workFolder -Recurse }
		$null = New-Item $workFolder -ItemType Directory -Force
		$null = New-Item $unpackedFolder -ItemType Directory -Force
		$null = New-PowerUpPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force
		$null = Add-PowerUpBuild -ScriptPath $v2scripts -Path $packageName -Build 2.0
	}
	AfterAll {
		if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.PowerUp') { Remove-Item $workFolder -Recurse }
	}
	Context "removing version 1.0 from existing package" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
		}
		AfterAll {
			$null = Remove-Item $packageNameTest
		}
		It "should remove build from existing package" {
			{ Remove-PowerUpBuild -Name $packageNameTest -Build 1.0 } | Should Not Throw
			Test-Path $packageNameTest | Should Be $true
		}
		$results = Get-ArchiveItem $packageNameTest
		It "build 1.0 should not exist" {
			'content\1.0' | Should Not BeIn $results.Path
		}
		It "build 2.0 should contain scripts from 2.0" {
			'content\2.0\2.sql' | Should BeIn $results.Path
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
	Context "removing version 2.0 from existing package" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
		}
		AfterAll {
			$null = Remove-Item $packageNameTest
		}
		It "should remove build from existing package" {
			{ Remove-PowerUpBuild -Name $packageNameTest -Build 2.0 } | Should Not Throw
			Test-Path $packageNameTest | Should Be $true
		}
		$results = Get-ArchiveItem $packageNameTest
		It "build 1.0 should contain scripts from 1.0" {
			'content\1.0\1.sql' | Should BeIn $results.Path
		}
		It "build 2.0 should not exist" {
			'content\2.0' | Should Not BeIn $results.Path
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
	Context "removing all versions from existing package" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
		}
		AfterAll {
			$null = Remove-Item $packageNameTest
		}
		It "should remove build from existing package" {
			{ Remove-PowerUpBuild -Name $packageNameTest -Build "1.0", "2.0"  } | Should Not Throw
			Test-Path $packageNameTest | Should Be $true
		}
		$results = Get-ArchiveItem $packageNameTest
		It "build 1.0 should not exist" {
			'content\1.0' | Should Not BeIn $results.Path
		}
		It "build 2.0 should not exist" {
			'content\2.0' | Should Not BeIn $results.Path
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
	Context "removing version 2.0 from existing package using pipeline" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
		}
		AfterAll {
			$null = Remove-Item $packageNameTest
		}
		It "should remove build from existing package" {
			{ $packageNameTest | Remove-PowerUpBuild -Build '2.0' } | Should Not Throw
			Test-Path $packageNameTest | Should Be $true
		}
		$results = Get-ArchiveItem $packageNameTest
		It "build 1.0 should contain scripts from 1.0" {
			'content\1.0\1.sql' | Should BeIn $results.Path
		}
		It "build 2.0 should not exist" {
			'content\2.0' | Should Not BeIn $results.Path
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
	Context "negative tests" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
			$null = New-PowerUpPackage -Name $packageNoPkgFile -Build 1.0 -ScriptPath $scriptFolder
			$null = Remove-ArchiveItem -Path $packageNoPkgFile -Item 'PowerUp.package.json'
		}
		AfterAll {
			$null = Remove-Item $packageNameTest
		}
		It "should throw error when package data file does not exist" {
			try {
				$null = Remove-PowerUpBuild -Name $packageNoPkgFile -Build 2.0
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*Incorrect package format*'
		}
		It "should throw error when package zip does not exist" {
			{ Remove-PowerUpBuild -Name ".\nonexistingpackage.zip" -Build 2.0 -ErrorAction Stop } | Should Throw
		}
		It "should output warning when build does not exist" {
			$null = Remove-PowerUpBuild -Name $packageNameTest -Build 3.0 -WarningVariable errorResult 3>$null
			$errorResult.Message -join ';' | Should BeLike '*not found in the package*'
		}
	}
}
