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

Describe "Get-PowerUpConfig tests" -Tag $commandName, UnitTests {
	It "Should throw when path does not exist" {
		{ Get-PowerUpConfig 'asdqweqsdfwer' } | Should throw
	}

	It "Should return an empty config by default" {
		$result = Get-PowerUpConfig
		$result.ApplicationName | Should Be $null
		$result.SqlInstance | Should Be $null
		$result.Database | Should Be $null
		$result.DeploymentMethod | Should Be $null
		$result.ConnectionTimeout | Should Be $null
		$result.Encrypt | Should Be $null
		$result.Credential | Should Be $null
		$result.Username | Should Be $null
		$result.Password | Should Be $null
		$result.SchemaVersionTable | Should Be 'dbo.SchemaVersions'
		$result.Silent | Should Be $null
		$result.Variables | Should Be $null
	}

	It "Should override properties in an empty config" {
		$result = Get-PowerUpConfig -Configuration @{ApplicationName = 'MyNewApp'; ConnectionTimeout = 3}
		$result.ApplicationName | Should Be 'MyNewApp'
		$result.SqlInstance | Should Be $null
		$result.Database | Should Be $null
		$result.DeploymentMethod | Should Be $null
		$result.ConnectionTimeout | Should Be 3
		$result.Encrypt | Should Be $null
		$result.Credential | Should Be $null
		$result.Username | Should Be $null
		$result.Password | Should Be $null
		$result.SchemaVersionTable | Should Be 'dbo.SchemaVersions'
		$result.Silent | Should Be $null
		$result.Variables | Should Be $null
	}

	It "Should return empty configuration from empty config file" {
		$result = Get-PowerUpConfig "$here\etc\empty_config.json"
		$result.ApplicationName | Should Be $null
		$result.SqlInstance | Should Be $null
		$result.Database | Should Be $null
		$result.DeploymentMethod | Should Be $null
		$result.ConnectionTimeout | Should Be $null
		$result.Encrypt | Should Be $null
		$result.Credential | Should Be $null
		$result.Username | Should Be $null
		$result.Password | Should Be $null
		$result.SchemaVersionTable | Should Be $null
		$result.Silent | Should Be $null
		$result.Variables | Should Be $null
	}

	It "Should return all configurations from the config file" {
		$result = Get-PowerUpConfig "$here\etc\full_config.json"
		$result.ApplicationName | Should Be "MyTestApp"
		$result.SqlInstance | Should Be "TestServer"
		$result.Database | Should Be "MyTestDB"
		$result.DeploymentMethod | Should Be "SingleTransaction"
		$result.ConnectionTimeout | Should Be 40
		$result.Encrypt | Should Be $null
		$result.Credential | Should Be $null
		$result.Username | Should Be "TestUser"
		$result.Password | Should Be "TestPassword"
		$result.SchemaVersionTable | Should Be "test.Table"
		$result.Silent | Should Be $true
		$result.Variables | Should Be $null
	}

	It "Should override configurations of the config file" {
		$result = Get-PowerUpConfig "$here\etc\full_config.json" -Configuration @{ApplicationName = 'MyNewApp'; ConnectionTimeout = 3; Database = $null}
		$result.ApplicationName | Should Be "MyNewApp"
		$result.SqlInstance | Should Be "TestServer"
		$result.Database | Should Be $null
		$result.DeploymentMethod | Should Be "SingleTransaction"
		$result.ConnectionTimeout | Should Be 3
		$result.Encrypt | Should Be $null
		$result.Credential | Should Be $null
		$result.Username | Should Be "TestUser"
		$result.Password | Should Be "TestPassword"
		$result.SchemaVersionTable | Should Be "test.Table"
		$result.Silent | Should Be $true
		$result.Variables | Should Be $null
	}

	
}
