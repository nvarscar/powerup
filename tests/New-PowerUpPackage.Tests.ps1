$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = if ($PSScriptRoot) { $PSScriptRoot } else {	(Get-Item . ).FullName }
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

. "$here\..\internal\Get-ArchiveItems.ps1"
. "$here\..\internal\New-TempWorkspaceFolder.ps1"
. "$here\..\internal\Expand-ArchiveItem.ps1"

$workFolder = New-TempWorkspaceFolder
$packagePath = "$workFolder\PowerUpTest.zip"
$scriptFolder = "$here\etc\install-tests\success"

Describe "$commandName tests" {	
	
	BeforeAll {
		if (Test-Path $packagePath) { Remove-Item $packagePath -Force }
	}
	AfterAll {
		if ($workFolder.Name -like 'PowerUpWorkspace*') { Remove-Item $workFolder -Recurse }
	}
	Context "testing package contents" {
		It "should create a package file" {
			$results = New-PowerUpPackage -ScriptPath "$here\etc\query1.sql" -Name $packagePath
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packagePath -Leaf)
			$results.FullName | Should Be (Get-Item $packagePath).FullName
			$results.ModuleVersion | Should Be (Get-Module PowerUp).Version
			Test-Path $packagePath | Should Be $true
		}
		It "should contain query files" {
			$results = Get-ArchiveItems $packagePath
			'query1.sql' | Should BeIn $results.Name
		}
		It "should contain module files" {
			$results = Get-ArchiveItems $packagePath
			'Modules\PowerUp\PowerUp.psd1' | Should BeIn $results.Path
			'Modules\PowerUp\bin\DbUp.dll' | Should BeIn $results.Path
		}
		It "should contain config files" {
			$results = Get-ArchiveItems $packagePath
			'PowerUp.config.json' | Should BeIn $results.Path
			'PowerUp.package.json' | Should BeIn $results.Path
		}
	}
	Context "testing configurations" {
		BeforeEach {
		}
		AfterEach {
			if ($workFolder.Name -like 'PowerUpWorkspace*') { Remove-Item "$workFolder\PowerUp.config.json" -Recurse }
		}
		It "should be able to apply config file" {
			$null = New-PowerUpPackage -ScriptPath "$here\etc\query1.sql" -Name $packagePath -ConfigurationFile "$here\etc\full_config.json" -Force
			$null = Expand-ArchiveItem -Path $packagePath -DestinationPath $workFolder -Item 'PowerUp.config.json'
			$config = Get-Content "$workFolder\PowerUp.config.json" | ConvertFrom-Json
			$config.ApplicationName | Should Be "MyTestApp"
			$config.SqlInstance | Should Be "TestServer"
			$config.Database | Should Be "MyTestDB"
			$config.DeploymentMethod | Should Be "SingleTransaction"
			$config.ConnectionTimeout | Should Be 40
			$config.Encrypt | Should Be $null
			$config.Credential | Should Be $null
			$config.Username | Should Be "TestUser"
			$config.Password | Should Be "TestPassword"
			$config.SchemaVersionTable | Should Be "test.Table"
			$config.Silent | Should Be $true
			$config.Variables | Should Be $null
		}
		It "should be able to apply custom config" {
			$null = New-PowerUpPackage -ScriptPath "$here\etc\query1.sql" -Name $packagePath -Configuration @{ApplicationName = "MyTestApp2"; ConnectionTimeout = 4; Database = $null } -Force
			$null = Expand-ArchiveItem -Path $packagePath -DestinationPath $workFolder -Item 'PowerUp.config.json'
			$config = Get-Content "$workFolder\PowerUp.config.json" | ConvertFrom-Json
			$config.ApplicationName | Should Be "MyTestApp2"
			$config.SqlInstance | Should Be $null
			$config.Database | Should Be $null
			$config.DeploymentMethod | Should Be $null
			$config.ConnectionTimeout | Should Be 4
			$config.Encrypt | Should Be $null
			$config.Credential | Should Be $null
			$config.Username | Should Be $null
			$config.Password | Should Be $null
			$config.SchemaVersionTable | Should Be $null
			$config.Silent | Should Be $null
			$config.Variables | Should Be $null
		}
		It "should be able to store variables" {
			$null = New-PowerUpPackage -ScriptPath "$here\etc\query1.sql" -Name $packagePath -Configuration @{ ApplicationName = 'FooBar' } -Variables @{ MyVar = 'foo'; MyBar = 1; MyNull = $null} -Force
			$null = Expand-ArchiveItem -Path $packagePath -DestinationPath $workFolder -Item 'PowerUp.config.json'
			$config = Get-Content "$workFolder\PowerUp.config.json" | ConvertFrom-Json
			$config.ApplicationName | Should Be 'FooBar'
			$config.SqlInstance | Should Be $null
			$config.Database | Should Be $null
			$config.DeploymentMethod | Should Be $null
			$config.ConnectionTimeout | Should Be $null
			$config.Encrypt | Should Be $null
			$config.Credential | Should Be $null
			$config.Username | Should Be $null
			$config.Password | Should Be $null
			$config.SchemaVersionTable | Should Be $null
			$config.Silent | Should Be $null
			$config.Variables.MyVar | Should Be 'foo'
			$config.Variables.MyBar | Should Be 1
			$config.Variables.MyNull | Should Be $null			
		}
	}
	Context "testing input scenarios" {
		It "should accept wildcard input" {
			$results = New-PowerUpPackage -ScriptPath "$here\etc\install-tests\*" -Build 'abracadabra' -Name $packagePath -Force
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packagePath -Leaf)
			$results.FullName | Should Be (Get-Item $packagePath).FullName
			$results.ModuleVersion | Should Be (Get-Module PowerUp).Version
			$results.Version | Should Be 'abracadabra'
			Test-Path $packagePath | Should Be $true
			$results = Get-ArchiveItems $packagePath
			'content\abracadabra\Cleanup.sql' | Should BeIn $results.Path
			'content\abracadabra\success\1.sql' | Should BeIn $results.Path
			'content\abracadabra\success\2.sql' | Should BeIn $results.Path
			'content\abracadabra\success\3.sql' | Should BeIn $results.Path
			'content\abracadabra\transactional-failure\1.sql' | Should BeIn $results.Path
			'content\abracadabra\transactional-failure\2.sql' | Should BeIn $results.Path
			'content\abracadabra\verification\select.sql' | Should BeIn $results.Path
		}
		It "should accept Get-Item <files> pipeline input" {
			$results = Get-Item "$scriptFolder\*" | New-PowerUpPackage -Build 'abracadabra' -Name $packagePath -Force
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packagePath -Leaf)
			$results.FullName | Should Be (Get-Item $packagePath).FullName
			$results.ModuleVersion | Should Be (Get-Module PowerUp).Version
			$results.Version | Should Be 'abracadabra'
			Test-Path $packagePath | Should Be $true
			$results = Get-ArchiveItems $packagePath
			'content\abracadabra\1.sql' | Should BeIn $results.Path
			'content\abracadabra\2.sql' | Should BeIn $results.Path
			'content\abracadabra\3.sql' | Should BeIn $results.Path
		}
		It "should accept Get-Item <files and folders> pipeline input" {
			$results = Get-Item "$here\etc\install-tests\*" | New-PowerUpPackage -Build 'abracadabra' -Name $packagePath -Force
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packagePath -Leaf)
			$results.FullName | Should Be (Get-Item $packagePath).FullName
			$results.ModuleVersion | Should Be (Get-Module PowerUp).Version
			$results.Version | Should Be 'abracadabra'
			Test-Path $packagePath | Should Be $true
			$results = Get-ArchiveItems $packagePath
			'content\abracadabra\Cleanup.sql' | Should BeIn $results.Path
			'content\abracadabra\success\1.sql' | Should BeIn $results.Path
			'content\abracadabra\success\2.sql' | Should BeIn $results.Path
			'content\abracadabra\success\3.sql' | Should BeIn $results.Path
			'content\abracadabra\transactional-failure\1.sql' | Should BeIn $results.Path
			'content\abracadabra\transactional-failure\2.sql' | Should BeIn $results.Path
			'content\abracadabra\verification\select.sql' | Should BeIn $results.Path
		}
		It "should accept Get-ChildItem pipeline input" {
			$results = Get-ChildItem "$scriptFolder" -File -Recurse | New-PowerUpPackage -Build 'abracadabra' -Name $packagePath -Force
			$results | Should Not Be $null
			$results.Name | Should Be (Split-Path $packagePath -Leaf)
			$results.FullName | Should Be (Get-Item $packagePath).FullName
			$results.ModuleVersion | Should Be (Get-Module PowerUp).Version
			$results.Version | Should Be 'abracadabra'
			Test-Path $packagePath | Should Be $true
			$results = Get-ArchiveItems $packagePath
			'content\abracadabra\1.sql' | Should BeIn $results.Path
			'content\abracadabra\2.sql' | Should BeIn $results.Path
			'content\abracadabra\3.sql' | Should BeIn $results.Path
		}
	}
	Context "runs negative tests" {
		It "should throw error when scripts with the same relative path is being added" {
			try {
				$result = New-PowerUpPackage -Name $packageNameTest -ScriptPath "$scriptFolder\*", "$scriptFolder\..\transactional-failure\*"
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*already exists inside this build*'
		}
		It "returns error when path does not exist" {
			try {
				$result = New-PowerUpPackage -ScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps'
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*The following path is not valid*'
		}
		It "returns error when config file does not exist" {
			try {
				$result = New-PowerUpPackage -ScriptPath "$here\etc\query1.sql" -ConfigurationFile 'asduwheiruwnfelwefo\sdfpoijfdsf.sps'
			}
			catch {
				$errorResult = $_
			}
			$errorResult.Exception.Message -join ';' | Should BeLike '*Config file * not found. Aborting.*'
		}
	}
}
