$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

. '..\internal\Get-ArchiveItems.ps1'
. '..\internal\New-TempWorkspaceFolder.ps1'

$workFolder = New-TempWorkspaceFolder
$unpackedFolder = Join-Path $workFolder "Unpacked"
$packageName = Join-Path $workFolder 'TempDeployment.zip'
$scriptFolder = Join-Path $here 'etc\install-tests\success'
$v1scripts = Join-Path $scriptFolder '1.sql'
$v2scripts = Join-Path $scriptFolder '2.sql'
$v3scripts = Join-Path $scriptFolder '3.sql'

Describe "$commandName tests" {	
	
	BeforeAll {
		$null = New-PowerUpPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force -ConfigurationFile "$here\etc\full_config.json"
		$null = Add-PowerUpBuild -ScriptPath $v2scripts -Path $packageName -Build 2.0
		$null = Add-PowerUpBuild -ScriptPath $v3scripts -Path $packageName -Build 3.0
	}
	AfterAll {
		if ($workFolder.Name -like 'PowerUpWorkspace*') { Remove-Item $workFolder -Recurse }
	}
	Context "Negative tests" {
		It "returns error when path does not exist" {
			{ Get-PowerUpPackage -Path 'asduwheiruwnfelwefo\sdfpoijfdsf.zip' -ErrorAction Stop} | Should Throw
		}
	}
	Context "Returns package properties" {
		It "returns existing builds" {
			$result = Get-PowerUpPackage -Path $packageName
			$result.Builds.Build | Should Be @('1.0', '2.0', '3.0')
			$result.Builds.Scripts.Name | Should Be @('1.0\1.sql', '2.0\2.sql', '3.0\3.sql')
			$result.Builds.Scripts.SourcePath | Should Be @((Get-Item $v1scripts).FullName, (Get-Item $v2scripts).FullName, (Get-Item $v3scripts).FullName)
		}
		It "should return specific build" {
			$result = Get-PowerUpPackage -Path $packageName -Build '1.0'
			$result.Builds.Build | Should Be '1.0'
			$result.Builds.Scripts.Name | Should Be '1.0\1.sql'
			$result.Builds.Scripts.SourcePath | Should Be (Get-Item $v1scripts).FullName
		}
		It "should return specific build and not return non-existing builds" {
			$result = Get-PowerUpPackage -Path $packageName -Build '1.0', '2.0', '4.0'
			$result.Builds.Build | Where-Object { $_ -eq '1.0'} | Should Not Be $null
			$result.Builds.Build | Where-Object { $_ -eq '2.0'} | Should Not Be $null
			$result.Builds.Build | Where-Object { $_ -eq '3.0'} | Should Be $null
			$result.Builds.Build | Where-Object { $_ -eq '4.0'} | Should Be $null
		}
		It "should return package info" {
			$result = Get-PowerUpPackage -Path $packageName
			$result.Name | Should Be 'TempDeployment.zip'
			$result.Path | Should Be $packageName
			$result.CreationTime | Should Not Be $null
			$result.Size | Should Not Be $null
			$result.Version | Should Be '3.0'
			$result.ModuleVersion | Should Be (Get-Module PowerUp).Version

		}
		It "should return package config" {
			$result = Get-PowerUpPackage -Path $packageName
			$result.Config | Should Not Be $null
			$result.Config.ApplicationName | Should Be "MyTestApp"
			$result.Config.SqlInstance | Should Be "TestServer"
			$result.Config.Database | Should Be "MyTestDB"
			$result.Config.DeploymentMethod | Should Be "SingleTransaction"
			$result.Config.ConnectionTimeout | Should Be 40
			$result.Config.Encrypt | Should Be $null
			$result.Config.Credential | Should Be $null
			$result.Config.Username | Should Be "TestUser"
			$result.Config.Password | Should Be "TestPassword"
			$result.Config.SchemaVersionTable | Should Be "test.Table"
			$result.Config.Silent | Should Be $true
			$result.Config.Variables | Should Be $null
		}
	}
	Context "Returns unpacked package properties" {
		BeforeAll {
			$null = New-Item $unpackedFolder -ItemType Directory
			Expand-Archive $packageName $unpackedFolder
		}
		AfterAll {
			Remove-Item -Path (Join-Path $unpackedFolder *) -Force -Recurse
		}
		It "returns existing builds" {
			$result = Get-PowerUpPackage -Path $unpackedFolder -Unpacked
			$result.Builds.Build | Should Be @('1.0', '2.0', '3.0')
			$result.Builds.Scripts.Name | Should Be @('1.0\1.sql', '2.0\2.sql', '3.0\3.sql')
			$result.Builds.Scripts.SourcePath | Should Be @((Get-Item $v1scripts).FullName, (Get-Item $v2scripts).FullName, (Get-Item $v3scripts).FullName)
		}
		It "should return specific build" {
			$result = Get-PowerUpPackage -Path $unpackedFolder -Build '1.0' -Unpacked
			$result.Builds.Build | Should Be '1.0'
			$result.Builds.Scripts.Name | Should Be '1.0\1.sql'
			$result.Builds.Scripts.SourcePath | Should Be (Get-Item $v1scripts).FullName
		}
		It "should return specific build and not return non-existing builds" {
			$result = Get-PowerUpPackage -Path $unpackedFolder -Build '1.0', '2.0', '4.0' -Unpacked
			$result.Builds.Build | Where-Object { $_ -eq '1.0'} | Should Not Be $null
			$result.Builds.Build | Where-Object { $_ -eq '2.0'} | Should Not Be $null
			$result.Builds.Build | Where-Object { $_ -eq '3.0'} | Should Be $null
			$result.Builds.Build | Where-Object { $_ -eq '4.0'} | Should Be $null
		}
		It "should return package info" {
			$result = Get-PowerUpPackage -Path $unpackedFolder -Unpacked
			$result.Name | Should Be 'Unpacked'
			$result.Path | Should Be $unpackedFolder
			$result.CreationTime | Should Not Be $null
			$result.Version | Should Be '3.0'
			$result.ModuleVersion.ToString() | Should Be (Get-Module PowerUp).Version.ToString()

		}
		It "should return package config" {
			$result = Get-PowerUpPackage -Path $unpackedFolder -Unpacked
			$result.Config | Should Not Be $null
			$result.Config.ApplicationName | Should Be "MyTestApp"
			$result.Config.SqlInstance | Should Be "TestServer"
			$result.Config.Database | Should Be "MyTestDB"
			$result.Config.DeploymentMethod | Should Be "SingleTransaction"
			$result.Config.ConnectionTimeout | Should Be 40
			$result.Config.Encrypt | Should Be $null
			$result.Config.Credential | Should Be $null
			$result.Config.Username | Should Be "TestUser"
			$result.Config.Password | Should Be "TestPassword"
			$result.Config.SchemaVersionTable | Should Be "test.Table"
			$result.Config.Silent | Should Be $true
			$result.Config.Variables | Should Be $null
		}
	}
}
