$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

Describe "$commandName tests" {
	It "Should return empty configuration when path does not exist" {
		$result = Get-PowerUpConfig 'asdqweqsdfwer'
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

	
}
