$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

. '..\internal\Get-ArchiveItems.ps1'

$packagePath = '.\etc\PowerUpTest.zip'
Describe "$commandName tests" {	
	
	BeforeAll {
		if (Test-Path $packagePath) { Remove-Item $packagePath -Force }
	}
	AfterAll {
		if (Test-Path $packagePath) { Remove-Item $packagePath -Force }
	}
	It "returns error when path does not exist" {
		try {
			$result = New-PowerUpPackage -ScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps' -ErrorVariable errorResult 2>$null
		}
		catch {}
		$errorResult.Exception.Message[0] | Should BeLike 'The following path is not valid*'
	}
	It "returns error when config file does not exist" {
		try {
			$result = New-PowerUpPackage -ScriptPath '.' -Config 'asduwheiruwnfelwefo\sdfpoijfdsf.sps' -ErrorVariable errorResult 2>$null
		}
		catch {}
		$errorResult.Exception.Message[0] | Should Be 'Configuration file does not exist'
	}
	It "should create a package file" {
		$results = New-PowerUpPackage -ScriptPath '.\etc\query1.sql' -Name $packagePath
		$results | Should Not Be $null
		$results.Name | Should Be (Split-Path $packagePath -Leaf)
		Test-Path $packagePath | Should Be $true
	}
	It "should contain query files" {
		$results = Get-ArchiveItems $packagePath
		$results | Where-Object Name -eq 'query1.sql' | Should Not Be $null
	}
	It "should contain module files" {
		$results = Get-ArchiveItems $packagePath
		$results | Where-Object Path -eq 'Modules\PowerUp\PowerUp.psd1' | Should Not Be $null
		$results | Where-Object Path -eq 'Modules\PowerUp\bin\DbUp.dll' | Should Not Be $null
	}
	It "should contain config files" {
		$results = Get-ArchiveItems $packagePath
		$results | Where-Object Path -eq 'PowerUp.config.json' | Should Not Be $null
		$results | Where-Object Path -eq 'PowerUp.package.json' | Should Not Be $null
	}
}
