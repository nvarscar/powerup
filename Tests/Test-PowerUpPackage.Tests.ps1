$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = if ($PSScriptRoot) { $PSScriptRoot } else {	(Get-Item . ).FullName }
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

. "$here\..\internal\Get-ArchiveItems.ps1"
. "$here\..\internal\New-TempWorkspaceFolder.ps1"
. "$here\..\internal\Remove-ArchiveItem.ps1"
. "$here\..\internal\Add-ArchiveItem.ps1"

$workFolder = New-TempWorkspaceFolder
$pkgTest = Join-Path $workFolder "TestPkg.zip"
$packageInvalid = Join-Path $workFolder "TestInvalidPkg.zip"
$scriptFolder = Join-Path $here "etc\install-tests\success"

Describe "$commandName tests" {
	AfterAll {
		if ($workFolder.Name -like 'PowerUpWorkspace*') { Remove-Item $workFolder -Recurse }
	}
	Context "tests packed packages" {
		BeforeAll {
			$null = New-PowerUpPackage -Name $pkgTest -Build 1.0 -ScriptPath $scriptFolder
			$null = New-PowerUpPackage -Name $packageInvalid -Build 1.0 -ScriptPath $scriptFolder\*
			$null = Remove-ArchiveItem -Path $packageInvalid -Item 'content\1.0\1.sql'
			$null = Add-ArchiveItem -Path $packageInvalid -Item "$scriptFolder\..\transactional-failure\2.sql" -InnerFolder 'content\1.0'
		}
		AfterAll {
			Remove-Item -Path $pkgTest -Force
			Remove-Item -Path $packageInvalid -Force
		}
		It "returns error when path does not exist" {
			try {
				$result = Test-PowerUpPackage -Path 'asduwheiruwnfelwefo\sdfpoijfdsf.sps'
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*Path not found:*'
		}
		It "should test a valid package file" {
			$result = Test-PowerUpPackage -Path $pkgTest
			$result.Package | Should Be $pkgTest
			$result.ModuleVersion.ToString() | Should Be (Get-Module PowerUp).Version.ToString()
			$result.PackageVersion | Should Be 1.0
			$result.IsValid | Should Be $true
			foreach ($r in $result.ValidationTests.Result) {
				$r | Should Be $true
			}
		}
		It "should test an invalid package file" {
			$result = Test-PowerUpPackage -Path $packageInvalid
			$result.IsValid | Should Be $false
			($result.ValidationTests | Where-Object Name -eq '1.0\1.sql').Result | Should Be $false
			($result.ValidationTests | Where-Object Name -eq '1.0\2.sql').Result | Should Be $false
			($result.ValidationTests | Where-Object Name -eq '1.0\3.sql').Result | Should Be $true
			
		}
	}
	Context "tests unpacked packages" {
		BeforeAll {
			$null = New-PowerUpPackage -Name $pkgTest -Build 1.0 -ScriptPath $scriptFolder
			Expand-Archive $pkgTest $workFolder
		}
		AfterAll {
			Remove-Item -Path (Join-Path $workFolder *) -Force -Recurse
		}
		It "returns error when path is not a container" {
			try {
				$result = Test-PowerUpPackage -Path "$here\etc\empty_config.json" -Unpacked
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*Path is not a container*'
		}
		It "should test a folder with unpacked package" {
			$result = Test-PowerUpPackage -Path $workFolder -Unpacked
			$result.Package | Should Be $workFolder.FullName
			$result.ModuleVersion.ToString() | Should Be (Get-Module PowerUp).Version.ToString()
			$result.PackageVersion | Should Be 1.0
			$result.IsValid | Should Be true
		}
		It "folder should remain after tests" {
			Test-Path $workFolder | Should Be $true
		}
		It "should test an unpacked package file" {
			$result = Test-PowerUpPackage -Path "$workFolder\PowerUp.package.json" -Unpacked
			$result.Package | Should Be "$workFolder\PowerUp.package.json"
			$result.ModuleVersion.ToString() | Should Be (Get-Module PowerUp).Version.ToString()
			$result.PackageVersion | Should Be 1.0
			$result.IsValid | Should Be true
		}
	}
}
