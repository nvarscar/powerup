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

. "$here\..\internal\functions\Get-ArchiveItem.ps1"

$workFolder = Join-Path "$here\etc" "$commandName.Tests.PowerUp"
$unpackedFolder = Join-Path $workFolder 'unpacked'

$packageName = Join-Path $workFolder 'TempDeployment.zip'
$v1scripts = "$here\etc\install-tests\success"

Describe "Update-PowerUpConfig tests" -Tag $commandName, UnitTests {
	BeforeAll {
		if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.PowerUp') { Remove-Item $workFolder -Recurse }
		$null = New-Item $workFolder -ItemType Directory -Force
		$null = New-Item $unpackedFolder -ItemType Directory -Force
		$null = New-PowerUpPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force -ConfigurationFile "$here\etc\full_config.json"
	}
	AfterAll {
		if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.PowerUp') { Remove-Item $workFolder -Recurse }
    }
	Context "Updating single config item (config/value pairs)" {
		It "updates config item with new value" {
			Update-PowerUpConfig -Path $packageName -ConfigName ApplicationName -Value 'MyNewApplication'
            $results = (Get-PowerUpPackage -Path $packageName).Configuration
            $results.ApplicationName | Should Be 'MyNewApplication'
        }
		It "updates config item with null value" {
			Update-PowerUpConfig -Path $packageName -ConfigName ApplicationName -Value $null
			$results = (Get-PowerUpPackage -Path $packageName).Configuration
			$results.ApplicationName | Should Be $null
        }
		It "should throw when config item is not specified" {
			{ Update-PowerUpConfig -Path $packageName -ConfigName $null -Value '123' } | Should throw
        }
		It "should throw when config item does not exist" {
			{ Update-PowerUpConfig -Path $packageName -ConfigName NonexistingItem -Value '123' } | Should throw
		}
    }
	Context "Updating config items using hashtable (values)" {
		It "updates config items with new values" {
			Update-PowerUpConfig -Path $packageName -Configuration @{ApplicationName = 'MyHashApplication'; Database = 'MyNewDb'}
            $results = (Get-PowerUpPackage -Path $packageName).Configuration
            $results.ApplicationName | Should Be 'MyHashApplication'
            $results.Database | Should Be 'MyNewDb'
        }
		It "updates config items with a null value" {
			Update-PowerUpConfig -Path $packageName -Configuration @{ApplicationName = $null; Database = $null}
            $results = (Get-PowerUpPackage -Path $packageName).Configuration
            $results.ApplicationName | Should Be $null
            $results.Database | Should Be $null
        }
		It "should throw when config item is not specified" {
			{ Update-PowerUpConfig -Path $packageName -Configuration $null } | Should throw
        }
		It "should throw when config item does not exist" {
			{ Update-PowerUpConfig -Path $packageName -Configuration @{NonexistingItem = '123' } } | Should throw
		}
    }
    Context "Updating config items using a file template" {
		It "updates config items with an empty config file" {
			Update-PowerUpConfig -Path $packageName -ConfigurationFile "$here\etc\empty_config.json"
            $results = (Get-PowerUpPackage -Path $packageName).Configuration
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
			Update-PowerUpConfig -Path $packageName -ConfigurationFile "$here\etc\full_config.json"
            $results = (Get-PowerUpPackage -Path $packageName).Configuration
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
    Context "Updating variables" {
		It "updates config variables with new hashtable" {
			Update-PowerUpConfig -Path $packageName -Variables @{foo='bar'} 
            $results = (Get-PowerUpPackage -Path $packageName).Configuration
            $results.Variables.foo | Should Be 'bar'
        }
		It "overrides specified config with a value from -Variables" {
			Update-PowerUpConfig -Path $packageName -Configuration @{Variables = @{ foo = 'bar'}} -Variables @{foo = 'bar2'}
			$results = (Get-PowerUpPackage -Path $packageName).Configuration
			$results.Variables.foo | Should Be 'bar2'
        }
    }
}
