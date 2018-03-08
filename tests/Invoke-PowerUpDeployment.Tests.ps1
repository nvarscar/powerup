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

. "$here\constants.ps1"

. "$here\..\internal\Get-ArchiveItem.ps1"
. "$here\..\internal\New-TempWorkspaceFolder.ps1"
. "$here\etc\Invoke-SqlCmd2.ps1"

$workFolder = Join-Path "$here\etc" "$commandName.Tests.PowerUp"
$unpackedFolder = Join-Path $workFolder 'unpacked'
$logTable = "testdeploymenthistory"
$cleanupScript = "$here\etc\install-tests\Cleanup.sql"
$tranFailScripts = "$here\etc\install-tests\transactional-failure"
$v1scripts = "$here\etc\install-tests\success\1.sql"
$v2scripts = "$here\etc\install-tests\success\2.sql"
$verificationScript = "$here\etc\install-tests\verification\select.sql"
$packageFileName = Join-Path $workFolder ".\PowerUp.package.json"
$cleanupPackageName = "$here\etc\TempCleanup.zip"
$outFile = "$here\etc\outLog.txt"


Describe "Invoke-PowerUpDeployment integration tests" -Tag $commandName, IntegrationTests {
	BeforeAll {
		if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.PowerUp') { Remove-Item $workFolder -Recurse }
		$null = New-Item $workFolder -ItemType Directory -Force
		$null = New-Item $unpackedFolder -ItemType Directory -Force
		$packageName = New-PowerUpPackage -Path (Join-Path $workFolder 'tmp.zip') -ScriptPath $tranFailScripts -Build 1.0 -Force
		$null = Expand-Archive -Path $packageName -DestinationPath $workFolder -Force
	}
	AfterAll {
		$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
		if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.PowerUp') { Remove-Item $workFolder -Recurse }
	}
	Context "testing transactional deployment of extracted package" {
		BeforeEach {
			$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
		}
		It "Should return errors and not create any objects" {
			#Running package
			$results = Invoke-PowerUpDeployment -PackageFile $packageFileName -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction -Silent
			$results.Successful | Should Be $false
			$results.Error.Message | Should Be "There is already an object named 'a' in the database."
			#Verifying objects
			$results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			$logTable | Should Not BeIn $results.name
			'a' | Should Not BeIn $results.name
			'b' | Should Not BeIn $results.name
			'c' | Should Not BeIn $results.name
			'd' | Should Not BeIn $results.name
		}
		
	}
	Context "testing non transactional deployment of extracted package" {
		It "Should return errors and create one object" {
			#Running package
			$results = Invoke-PowerUpDeployment -PackageFile $packageFileName -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -DeploymentMethod NoTransaction -Silent
			$results.Successful | Should Be $false
			$results.Error.Message | Should Be "There is already an object named 'a' in the database."
			#Verifying objects
			$results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			$logTable | Should BeIn $results.name
			'a' | Should BeIn $results.name
			'b' | Should Not BeIn $results.name
			'c' | Should Not BeIn $results.name
			'd' | Should Not BeIn $results.name
		}
	}
	Context "testing script deployment" {
		BeforeAll {
			$p1 = New-PowerUpPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
			$p2 = New-PowerUpPackage -ScriptPath $v2scripts -Name "$workFolder\pv2" -Build 2.0 -Force
			$outputFile = "$workFolder\log.txt"
			$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
		}
		It "should deploy version 1.0" {
			$results = Invoke-PowerUpDeployment -ScriptPath $v1scripts -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -Silent
			$results.Successful | Should Be $true
			$results.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
			#Verifying objects
			$results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			$logTable | Should BeIn $results.name
			'a' | Should BeIn $results.name
			'b' | Should BeIn $results.name
			'c' | Should Not BeIn $results.name
			'd' | Should Not BeIn $results.name
		}
		It "should deploy version 2.0" {
			$results = Invoke-PowerUpDeployment -ScriptPath $v2scripts -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -Silent
			$results.Successful | Should Be $true
			$results.Scripts.Name | Should Be (Resolve-Path $v2scripts).Path
			#Verifying objects
			$results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			$logTable | Should BeIn $results.name
			'a' | Should BeIn $results.name
			'b' | Should BeIn $results.name
			'c' | Should BeIn $results.name
			'd' | Should BeIn $results.name
		}
	}
	Context "testing timeouts" {
		BeforeAll {
			$file = "$workFolder\delay.sql"
			"WAITFOR DELAY '00:00:03'; PRINT ('Successful!')" | Out-File $file
		}
		BeforeEach {
			$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
		}
		It "should return timeout error " {
			$results = Invoke-PowerUpDeployment -ScriptPath "$workFolder\delay.sql" -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 2
			$results.Successful | Should Be $false
			$output = Get-Content "$workFolder\log.txt" -Raw
			$output | Should BeLike '*Execution Timeout Expired*'
			$output | Should Not BeLike '*Successful!*'
		}
		It "should successfully run within specified timeout" {
			$results = Invoke-PowerUpDeployment -ScriptPath "$workFolder\delay.sql" -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 6
			$results.Successful | Should Be $true
			$results.Scripts.Name | Should Be "$workFolder\delay.sql"
			$output = Get-Content "$workFolder\log.txt" -Raw
			$output | Should Not BeLike '*Execution Timeout Expired*'
			$output | Should BeLike '*Successful!*'
		}
		It "should successfully run with infinite timeout" {
			$results = Invoke-PowerUpDeployment -ScriptPath "$workFolder\delay.sql" -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 0
			$results.Successful | Should Be $true
			$results.Scripts.Name | Should Be "$workFolder\delay.sql"
			$output = Get-Content "$workFolder\log.txt" -Raw
			$output | Should Not BeLike '*Execution Timeout Expired*'
			$output | Should BeLike '*Successful!*'
		}
	}
	Context  "$commandName whatif tests" {
		BeforeAll {
			$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
		}
		AfterAll {
		}
		It "should deploy nothing" {
			$results = Invoke-PowerUpDeployment -ScriptPath $v1scripts -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -Silent -WhatIf
			$results | Should BeNullOrEmpty
			#Verifying objects
			$results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			$logTable | Should Not BeIn $results.name
			'a' | Should Not BeIn $results.name
			'b' | Should Not BeIn $results.name
			'c' | Should Not BeIn $results.name
			'd' | Should Not BeIn $results.name
		}
	}
	Context "testing deployment without specifying SchemaVersion table" {
		BeforeAll {
			$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
		}
		AfterAll {
			$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -Query "IF OBJECT_ID('SchemaVersions') IS NOT NULL DROP TABLE SchemaVersions"
		}
		It "should deploy version 1.0" {
			$before = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			$rowsBefore = ($before | Measure-Object).Count
			$results = Invoke-PowerUpDeployment -ScriptPath $v1scripts -SqlInstance $script:instance1 -Database $script:database1 -Silent
			$results.Successful | Should Be $true
			$results.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
			#Verifying objects
			$results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			'SchemaVersions' | Should BeIn $results.name
			'a' | Should BeIn $results.name
			'b' | Should BeIn $results.name
			'c' | Should Not BeIn $results.name
			'd' | Should Not BeIn $results.name
			($results | Measure-Object).Count | Should Be ($rowsBefore + 3)
		}
		It "should deploy version 2.0" {
			$before = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			$rowsBefore = ($before | Measure-Object).Count
			$results = Invoke-PowerUpDeployment -ScriptPath $v2scripts -SqlInstance $script:instance1 -Database $script:database1 -Silent
			$results.Successful | Should Be $true
			$results.Scripts.Name | Should Be (Resolve-Path $v2scripts).Path
			#Verifying objects
			$results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			'SchemaVersions' | Should BeIn $results.name
			'a' | Should BeIn $results.name
			'b' | Should BeIn $results.name
			'c' | Should BeIn $results.name
			'd' | Should BeIn $results.name
			($results | Measure-Object).Count | Should Be ($rowsBefore + 2)
		}
	}
	Context "testing deployment with no history`: SchemaVersion is null" {
		BeforeEach {
			$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
		}
		AfterEach {
			$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -Query "IF OBJECT_ID('SchemaVersions') IS NOT NULL DROP TABLE SchemaVersions"
		}
		It "should deploy version 1.0 without creating SchemaVersions" {
			$before = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			$rowsBefore = ($before | Measure-Object).Count
			$results = Invoke-PowerUpDeployment -ScriptPath $v1scripts  -SqlInstance $script:instance1 -Database $script:database1 -Silent -SchemaVersionTable $null
			$results.Successful | Should Be $true
			$results.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
			#Verifying objects
			$results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			'SchemaVersions' | Should Not BeIn $results.name
			'a' | Should BeIn $results.name
			'b' | Should BeIn $results.name
			'c' | Should Not BeIn $results.name
			'd' | Should Not BeIn $results.name
			($results | Measure-Object).Count | Should Be ($rowsBefore + 2)
		}
	}
}
