$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

Describe "$commandName tests" {
	It "Should return empty configuration when path does not exist" {
		$result = Get-PowerUpConfig 'asdqweqsdfwer'
		$result.ApplicationName | Should Be $null
		$result.Build | Should Not Be $null
		$result.SqlInstance | Should Be $null
		$result.Database | Should Be $null
		$result.DeploymentMethod | Should Be $null
		$result.ConnectionTimeout | Should Be $null
		$result.Encrypt | Should Be $null
		$result.Credential | Should Be $null
		$result.Username | Should Be $null
		$result.Password | Should Be $null
		$result.LogToTable | Should Be $null
		$result.Silent | Should Be $null
		$result.Variables | Should Be $null
	}

	
}
