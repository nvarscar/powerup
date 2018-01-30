$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

. '.\constants.ps1'

. '..\internal\Get-ArchiveItems.ps1'
. '..\internal\New-TempWorkspaceFolder.ps1'

$workFolder = New-TempWorkspaceFolder

$scriptFolder = '.\etc\install-tests\success'
$v1scripts = Join-Path $scriptFolder '1.sql'
$v2scripts = Join-Path $scriptFolder '2.sql'
$packageName = Join-Path $workFolder 'TempDeployment.zip'
$packageNameTest = "$packageName.test.zip"

Describe "$commandName tests" {
	BeforeAll {
		$null = New-PowerUpPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force
	}
	AfterAll {
		if ($workFolder.Name -like 'PowerUpWorkspace*') { Remove-Item $workFolder -Recurse }
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
		$results = Get-ArchiveItems $packageNameTest
		It "build 1.0 should only contain scripts from 1.0" {
			$results | Where-Object Path -eq 'content\1.0\1.sql' | Should Not Be $null
			$results | Where-Object Path -eq 'content\1.0\2.sql' | Should Be $null
		}
		It "build 2.0 should only contain scripts from 2.0" {
			$results | Where-Object Path -eq 'content\2.0\2.sql' | Should Not Be $null
			$results | Where-Object Path -eq 'content\2.0\1.sql' | Should Be $null
		}
		It "should contain module files" {
			$results | Where-Object Path -eq 'Modules\PowerUp\PowerUp.psd1' | Should Not Be $null
			$results | Where-Object Path -eq 'Modules\PowerUp\bin\DbUp.dll' | Should Not Be $null
		}
		It "should contain config files" {
			$results | Where-Object Path -eq 'PowerUp.config.json' | Should Not Be $null
			$results | Where-Object Path -eq 'PowerUp.package.json' | Should Not Be $null
		}
	}
	Context "adding new files only based on source path" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
		}
		AfterAll {
			$null = Remove-Item $packageNameTest
		}
		It "should add new build to existing package" {
			$results = Add-PowerUpBuild -ScriptPath $scriptFolder -Name $packageNameTest -Build 2.0 -NewOnly
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packageNameTest -Leaf)
			Test-Path $packageNameTest | Should Be $true
		}
		$results = Get-ArchiveItems $packageNameTest
		It "build 1.0 should only contain scripts from 1.0" {
			$results | Where-Object Path -eq 'content\1.0\1.sql' | Should Not Be $null
			$results | Where-Object Path -eq 'content\1.0\2.sql' | Should Be $null
		}
		It "build 2.0 should only contain scripts from 2.0" {
			$results | Where-Object Path -eq 'content\2.0\2.sql' | Should Not Be $null
			$results | Where-Object Path -eq 'content\2.0\1.sql' | Should Be $null
		}
		It "should contain module files" {
			$results | Where-Object Path -eq 'Modules\PowerUp\PowerUp.psd1' | Should Not Be $null
			$results | Where-Object Path -eq 'Modules\PowerUp\bin\DbUp.dll' | Should Not Be $null
		}
		It "should contain config files" {
			$results | Where-Object Path -eq 'PowerUp.config.json' | Should Not Be $null
			$results | Where-Object Path -eq 'PowerUp.package.json' | Should Not Be $null
		}
	}
	Context "adding new files only based on uniqueness (hash)" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
			$null = Copy-Item $v1scripts "$workFolder\Test.sql"
		}
		AfterAll {
			$null = Remove-Item $packageNameTest
			$null = Remove-Item "$workFolder\Test.sql"
		}
		It "should add new build to existing package" {
			$results = Add-PowerUpBuild -ScriptPath $scriptFolder, "$workFolder\Test.sql" -Name $packageNameTest -Build 2.0 -UniqueOnly
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packageNameTest -Leaf)
			Test-Path $packageNameTest | Should Be $true
		}
		It "should add new build to existing package based on changes in the file" {
			"nope" | Out-File "$workFolder\Test.sql" -Append
			$results = Add-PowerUpBuild -ScriptPath $scriptFolder, "$workFolder\Test.sql" -Name $packageNameTest -Build 3.0 -UniqueOnly
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packageNameTest -Leaf)
			Test-Path $packageNameTest | Should Be $true
		}
		$results = Get-ArchiveItems $packageNameTest
		It "build 1.0 should only contain scripts from 1.0" {
			$results | Where-Object Path -eq 'content\1.0\1.sql' | Should Not Be $null
			$results | Where-Object Path -eq 'content\1.0\2.sql' | Should Be $null
		}
		It "build 2.0 should only contain scripts from 2.0" {
			$results | Where-Object Path -eq 'content\2.0\2.sql' | Should Not Be $null
			$results | Where-Object Path -eq 'content\2.0\1.sql' | Should Be $null
			$results | Where-Object Path -eq 'content\2.0\Test.sql' | Should Be $null
		}
		It "build 3.0 should only contain scripts from 3.0" {
			$results | Where-Object Path -eq 'content\3.0\Test.sql' | Should Not Be $null
			$results | Where-Object Path -eq 'content\3.0\2.sql' | Should Be $null
			$results | Where-Object Path -eq 'content\3.0\1.sql' | Should Be $null
		}
		It "should contain module files" {
			$results | Where-Object Path -eq 'Modules\PowerUp\PowerUp.psd1' | Should Not Be $null
			$results | Where-Object Path -eq 'Modules\PowerUp\bin\DbUp.dll' | Should Not Be $null
		}
		It "should contain config files" {
			$results | Where-Object Path -eq 'PowerUp.config.json' | Should Not Be $null
			$results | Where-Object Path -eq 'PowerUp.package.json' | Should Not Be $null
		}
	}
}
