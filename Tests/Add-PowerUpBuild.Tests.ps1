$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

. '.\constants.ps1'

. '..\internal\Get-ArchiveItems.ps1'
. '..\internal\New-TempWorkspaceFolder.ps1'

$workFolder = New-TempWorkspaceFolder

$v1scripts = '.\etc\install-tests\success\1.sql'
$v2scripts = '.\etc\install-tests\success\2.sql'
$packageName = Join-Path $workFolder 'TempDeployment.zip'

Describe "$commandName tests" {
	BeforeAll {
		$null = New-PowerUpPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force
	}
	AfterAll {
		if ($workFolder.Name -like 'PowerUpWorkspace*') { Remove-Item $workFolder -Recurse }
	}
	Context "adding version 2.0 to existing package" {
		It "should add new build to existing package" {
			$results = Add-PowerUpBuild -ScriptPath $v2scripts -Name $packageName -Build 2.0
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packageName -Leaf)
			Test-Path $packageName | Should Be $true
		}
	}
	Context "Verifying new package" {
		$results = Get-ArchiveItems $packageName
		It "should contain query files from version 1.0" {
			$results | Where-Object Path -eq 'content\2.0\2.sql' | Should Not Be $null
		}
		It "should contain query files from version 2.0" {
			$results | Where-Object Path -eq 'content\2.0\2.sql' | Should Not Be $null
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
