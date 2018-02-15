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
			$results | Where-Object Path -eq "content\2.0\$(Split-Path $scriptFolder -Leaf)\2.sql" | Should Not Be $null
			$results | Where-Object Path -eq "content\2.0\$(Split-Path $scriptFolder -Leaf)\1.sql" | Should Be $null
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
			$results | Where-Object Path -eq "content\2.0\$(Split-Path $scriptFolder -Leaf)\2.sql" | Should Not Be $null
			$results | Where-Object Path -eq "content\2.0\$(Split-Path $scriptFolder -Leaf)\1.sql" | Should Be $null
			$results | Where-Object Path -eq 'content\2.0\Test.sql' | Should Be $null
		}
		It "build 3.0 should only contain scripts from 3.0" {
			$results | Where-Object Path -eq 'content\3.0\Test.sql' | Should Not Be $null
			$results | Where-Object Path -eq "content\3.0\$(Split-Path $scriptFolder -Leaf)\2.sql" | Should Be $null
			$results | Where-Object Path -eq "content\3.0\$(Split-Path $scriptFolder -Leaf)\1.sql" | Should Be $null
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
	Context "negative tests" {
		BeforeAll {
			$null = Copy-Item $packageName $packageNameTest
		}
		AfterAll {
			$null = Remove-Item $packageNameTest
		}
		It "should show warning when there are no new files" {
			try {
				$result = Add-PowerUpBuild -Name $packageNameTest -ScriptPath $v1scripts -UniqueOnly -WarningVariable warningResult 3>$null
			}
			catch {}
			$warningResult.Message -join ';' | Should BeLike '*No scripts have been selected, the original file is unchanged.*'
		}
		It "should throw error when package data file does not exist" {
			try {
				$result = Add-PowerUpBuild -Name ".\etc\pkg_nopkgfile.zip" -ScriptPath $v2scripts -SkipValidation -ErrorVariable errorResult 2>$null
			}
			catch {}
			$errorResult.Exception.Message -join ';' | Should BeLike '*Package file * not found*'
		}
		It "should throw error when package zip does not exist" {
			try {
				$result = Add-PowerUpBuild -Name ".\nonexistingpackage.zip" -ScriptPath $v1scripts -ErrorVariable errorResult 2>$null
			}
			catch {}
			$errorResult.Exception.Message -join ';' | Should BeLike '*Package * not found. Aborting build*'
		}
		It "should throw error when path cannot be resolved" {
			try {
				$result = Add-PowerUpBuild -Name $packageNameTest -ScriptPath ".\nonexistingsourcefiles.sql" -ErrorVariable errorResult 2>$null
			}
			catch {}
			$errorResult.Exception.Message -join ';' | Should BeLike '*The following path is not valid*'
		}
		It "should throw error when scripts with the same relative path is being added" {
			try {
				$result = Add-PowerUpBuild -Name $packageNameTest -ScriptPath "$scriptFolder\*", "$scriptFolder\..\transactional-failure\*" 2>$null
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*already exists inside this build*'
		}
	}
}
