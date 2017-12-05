$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

. '.\constants.ps1'

. '..\internal\Get-ArchiveItems.ps1'
. '..\internal\New-TempWorkspaceFolder.ps1'
. '.\etc\Invoke-SqlCmd2.ps1'

$workFolder = New-TempWorkspaceFolder

$logTable = 'testdeploymenthistory'
$cleanupScript = '.\etc\install-tests\Cleanup.sql'
$tranFailScripts = '.\etc\install-tests\transactional-failure'
$v1scripts = '.\etc\install-tests\success\1.sql'
$v2scripts = '.\etc\install-tests\success\2.sql'
$verificationScript = '.\etc\install-tests\verification\select.sql'
$packageName = Join-Path $workFolder 'TempDeployment.zip'
$cleanupPackageName = '.\etc\TempCleanup.zip'
$outFile = '.\etc\outLog.txt'


Describe "$commandName tests" {
	BeforeAll {
		$null = New-PowerUpPackage -ScriptPath $tranFailScripts -Name $packageName -Build 1.0 -Force
	}
	AfterAll {
		$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
		if ($workFolder.Name -like 'PowerUpWorkspace*') { Remove-Item $workFolder -Recurse }
	}
	Context "testing transactional deployment" {
		BeforeEach {
			$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
		}
		It "Should return errors and not create any objects" {
			#Running package
			$results = Install-PowerUpPackage $packageName -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction -Silent
			$results.Successful | Should Be $false
			$results.Error.Message | Should Be "There is already an object named 'a' in the database."
			#Verifying objects
			$results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			$results.name | Where-Object { $_ -eq $logTable } | Should Be $null
			$results.name | Where-Object { $_ -eq 'a' } | Should Be $null
			$results.name | Where-Object { $_ -eq 'b' } | Should Be $null
			$results.name | Where-Object { $_ -eq 'c' } | Should Be $null
			$results.name | Where-Object { $_ -eq 'd' } | Should Be $null
		}
		
	}
	Context "testing non transactional deployment" {
		It "Should return errors and create one object" {
			#Running package
			$results = Install-PowerUpPackage $packageName -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -DeploymentMethod NoTransaction -Silent
			$results.Successful | Should Be $false
			$results.Error.Message | Should Be "There is already an object named 'a' in the database."
			#Verifying objects
			$results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
			$results.name | Where-Object { $_ -eq $logTable } | Should Not Be $null
			$results.name | Where-Object { $_ -eq 'a' } | Should Not Be $null
			$results.name | Where-Object { $_ -eq 'b' } | Should Be $null
			$results.name | Where-Object { $_ -eq 'c' } | Should Be $null
			$results.name | Where-Object { $_ -eq 'd' } | Should Be $null
		}
	}
	Context "testing regular deployment" {
		BeforeAll {
			$p1 = New-PowerUpPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
			$p2 = New-PowerUpPackage -ScriptPath $v2scripts -Name "$workFolder\pv2" -Build 2.0 -Force
			$outputFile = "$workFolder\log.txt"
			$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
		}
		It "should deploy version 1.0" {
			$results = Install-PowerUpPackage "$workFolder\pv1.zip" -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
			$results.Successful | Should Be $true
			$results.Scripts.Name | Should Be ((Get-Item $v1scripts).Name | ForEach-Object {'1.0\' + $_})
			$output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
			$output | Should Be (Get-Content '.\etc\log1.txt')
		}
		It "should deploy version 2.0" {
			$results = Install-PowerUpPackage "$workFolder\pv2.zip" -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
			$results.Successful | Should Be $true
			$results.Scripts.Name | Should Be ((Get-Item $v2scripts).Name | ForEach-Object { '2.0\' + $_ })
			$output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
			$output | Should Be (Get-Content '.\etc\log2.txt')
		}
	}
	Context "testing timeouts" {
		BeforeAll {
			$file = "$workFolder\delay.sql"
			"WAITFOR DELAY '00:00:03'; PRINT ('Successful!')" | Out-File $file
			$null = New-PowerUpPackage -ScriptPath $file -Name "$workFolder\delay" -Build 1.0 -Force -ExecutionTimeout 2
		}
		BeforeEach {
			$null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
		}
		It "should return timeout error " {
			$results = Install-PowerUpPackage "$workFolder\delay.zip" -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
			$results.Successful | Should Be $false
			$output = Get-Content "$workFolder\log.txt" -Raw
			$output | Should BeLike '*Execution Timeout Expired*'
			$output | Should Not BeLike '*Successful!*'
		}
		It "should successfully run within specified timeout" {
			$results = Install-PowerUpPackage "$workFolder\delay.zip" -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 6
			$results.Successful | Should Be $true
			$results.Scripts.Name | Should Be '1.0\delay.sql'
			$output = Get-Content "$workFolder\log.txt" -Raw
			$output | Should Not BeLike '*Execution Timeout Expired*'
			$output | Should BeLike '*Successful!*'
		}
		It "should successfully run with infinite timeout" {
			$results = Install-PowerUpPackage "$workFolder\delay.zip" -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 0
			$results.Successful | Should Be $true
			$results.Scripts.Name | Should Be '1.0\delay.sql'
			$output = Get-Content "$workFolder\log.txt" -Raw
			$output | Should Not BeLike '*Execution Timeout Expired*'
			$output | Should BeLike '*Successful!*'
		}
	}
}
