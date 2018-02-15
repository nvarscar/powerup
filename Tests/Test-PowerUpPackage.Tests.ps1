$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

. '..\internal\Get-ArchiveItems.ps1'
. '..\internal\New-TempWorkspaceFolder.ps1'

$workFolder = New-TempWorkspaceFolder

Describe "$commandName tests" {
	BeforeAll {
		Expand-Archive '.\etc\pkg_valid.zip' $workFolder
	}
	AfterAll {
		if ($workFolder.Name -like 'PowerUpWorkspace*') { Remove-Item $workFolder -Recurse }
	}
	Context "tests packed packages" {
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
			$result = Test-PowerUpPackage -Path '.\etc\pkg_valid.zip'
			$result.Package | Should Be '.\etc\pkg_valid.zip'
			$result.IsValid | Should Be $true
			foreach ($r in $result.ValidationTests.Result) {
				$r | Should Be $true
			}
		}
		It "should test an invalid package file" {
			$result = Test-PowerUpPackage -Path '.\etc\pkg_notvalid.zip'
			$result.IsValid | Should Be $false
			($result.ValidationTests | Where-Object Name -EQ '1.0\0_Cleanup.sql').Result | Should Be $false
			($result.ValidationTests | Where-Object Name -EQ '1.0\Scrip1-Create Table.sql').Result | Should Be $false
			
		}
	}
	Context "tests unpacked packages" {
		It "returns error when path is not a container" {
			try {
				$result = Test-PowerUpPackage -Path '.\etc\pkg_valid.zip' -Unpacked
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*Path is not a container*'
		}
		It "should test a folder with unpacked package" {
			$result = Test-PowerUpPackage -Path $workFolder -Unpacked
			$result.Package | Should Be $workFolder.FullName
			$result.IsValid | Should Be true
		}
		It "folder should remain after tests" {
			Test-Path $workFolder | Should Be $true
		}
		It "should test an unpacked package file" {
			$result = Test-PowerUpPackage -Path "$workFolder\PowerUp.package.json" -Unpacked
			$result.Package | Should Be "$workFolder\PowerUp.package.json"
			$result.IsValid | Should Be true
		}
	}
}
