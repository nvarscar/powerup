$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

. '..\internal\Get-ArchiveItems.ps1'

$tempFolder = "PowerUpTestWorkspace" + [string](Get-Random(99999))
$tempPath = [System.IO.Path]::GetTempPath()
$tempPath = Join-Path $tempPath $tempFolder

Describe "$commandName tests" {
	BeforeAll {
		$workFolder = New-Item $tempPath -ItemType Directory
		Expand-Archive '.\etc\pkg_valid.zip' $workFolder
	}
	AfterAll {
		Remove-Item $tempPath -Recurse -Force
	}
	Context "tests packed packages" {
		It "returns error when path does not exist" {
			try {
				$result = Test-PowerUpPackage -Path 'asduwheiruwnfelwefo\sdfpoijfdsf.sps' -ErrorVariable errorResult 2>$null
			}
			catch { }
			$errorResult.Exception.Message[0] | Should BeLike 'Path not found:*'
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
				$result = Test-PowerUpPackage -Path '.\etc\pkg_valid.zip' -Unpacked -ErrorVariable errorResult 2>$null
			}
			catch { }
			$errorResult.Exception.Message[0] | Should BeLike 'Path is not a container*'
		}
		It "should test a folder with unpacked package" {
			$result = Test-PowerUpPackage -Path $tempPath -Unpacked
			$result.Package | Should Be $tempPath
			$result.IsValid | Should Be true
		}
		It "folder should remain after tests" {
			Test-Path $tempPath | Should Be $true
		}
		It "should test an unpacked package file" {
			$result = Test-PowerUpPackage -Path "$tempPath\PowerUp.package.json" -Unpacked
			$result.Package | Should Be "$tempPath\PowerUp.package.json"
			$result.IsValid | Should Be true
		}
	}
}
