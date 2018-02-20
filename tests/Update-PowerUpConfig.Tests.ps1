$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")

$here = if ($PSScriptRoot) { $PSScriptRoot } else {	(Get-Item . ).FullName }
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

. "$here\..\internal\Get-ArchiveItems.ps1"
. "$here\..\internal\New-TempWorkspaceFolder.ps1"

$workFolder = New-TempWorkspaceFolder
$unpackedFolder = Join-Path $workFolder "Unpacked"
$packageName = Join-Path $workFolder 'TempDeployment.zip'
$v1scripts = "$here\etc\install-tests\success"

Describe "Update-PowerUpConfig tests" {
	BeforeAll {
		$null = New-PowerUpPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force -ConfigurationFile "$here\etc\full_config.json"
	}
	AfterAll {
		if ($workFolder.Name -like 'PowerUpWorkspace*') { Remove-Item $workFolder -Recurse }
    }
	Context "Updating single config item (config/value pairs)" {
		It "updates config item with new value" {
			{ Update-PowerUpConfig -Path $packageName -Config ApplicationName -Value 'MyNewApplication' } | Should Not throw
            $results = (Get-PowerUpPackage -Path $packageName).Config
            $results.ApplicationName | Should Be 'MyNewApplication'
        }
		It "updates config item with null value" {
			{ Update-PowerUpConfig -Path $packageName -Config ApplicationName -Value $null } | Should Not throw
			$results = (Get-PowerUpPackage -Path $packageName).Config
			$results.ApplicationName | Should Be $null
        }
		It "should throw when config item is not specified" {
			{ Update-PowerUpConfig -Path $packageName -Config $null -Value '123' } | Should throw
        }
		It "should throw when config item does not exist" {
			{ Update-PowerUpConfig -Path $packageName -Config NonexistingItem -Value '123' } | Should throw
		}
    }
	Context "Updating config items using hashtable (values)" {
		It "updates config items with new values" {
			{ Update-PowerUpConfig -Path $packageName -Values @{ApplicationName = 'MyHashApplication'; Database = 'MyNewDb'} } | Should Not throw
            $results = (Get-PowerUpPackage -Path $packageName).Config
            $results.ApplicationName | Should Be 'MyHashApplication'
            $results.Database | Should Be 'MyNewDb'
        }
		It "updates config items with a null value" {
			{ Update-PowerUpConfig -Path $packageName -Values @{ApplicationName = $null; Database = $null} } | Should Not throw
            $results = (Get-PowerUpPackage -Path $packageName).Config
            $results.ApplicationName | Should Be $null
            $results.Database | Should Be $null
        }
		It "should throw when config item is not specified" {
			{ Update-PowerUpConfig -Path $packageName -Values $null } | Should throw
        }
		It "should throw when config item does not exist" {
			{ Update-PowerUpConfig -Path $packageName -Values @{NonexistingItem = '123' } } | Should throw
		}
    }
    Context "Updating config items using a file template" {
		It "updates config items with an empty config file" {
			{ Update-PowerUpConfig -Path $packageName -ConfigurationFile "$here\etc\empty_config.json"} | Should Not throw
            $results = (Get-PowerUpPackage -Path $packageName).Config
            $results.ApplicationName | Should Be $null
            $results.SqlInstance | Should Be $null
            $results.Database | Should Be $null
            $results.DeploymentMethod | Should Be $null
            $results.ConnectionTimeout | Should Be $null
            $results.Encrypt | Should Be $null
            $results.Credential | Should Be $null
            $results.Username | Should Be $null
            $results.Password | Should Be $null
            $results.SchemaVersionTable | Should Be $null
            $results.Silent | Should Be $null
            $results.Variables | Should Be $null
        }
		It "updates config items with a proper config file" {
			{ Update-PowerUpConfig -Path $packageName -ConfigurationFile "$here\etc\full_config.json"} | Should Not throw
            $results = (Get-PowerUpPackage -Path $packageName).Config
            $results.ApplicationName | Should Be "MyTestApp"
            $results.SqlInstance | Should Be "TestServer"
            $results.Database | Should Be "MyTestDB"
            $results.DeploymentMethod | Should Be "SingleTransaction"
            $results.ConnectionTimeout | Should Be 40
            $results.Encrypt | Should Be $null
            $results.Credential | Should Be $null
            $results.Username | Should Be "TestUser"
            $results.Password | Should Be "TestPassword"
            $results.SchemaVersionTable | Should Be "test.Table"
            $results.Silent | Should Be $true
            $results.Variables | Should Be $null
        }
		It "should throw when config file is not specified" {
			{ Update-PowerUpConfig -Path $packageName -ConfigurationFile $null } | Should throw
        }
		It "should throw when config items are wrong in the file" {
			{ Update-PowerUpConfig -Path $packageName -ConfigurationFile "$here\etc\wrong_config.json" } | Should throw
        }
        It "should throw when config file does not exist" {
            { Update-PowerUpConfig -Path $packageName -ConfigurationFile "$here\etc\nonexistingconfig.json" } | Should throw
        }
    }
}
