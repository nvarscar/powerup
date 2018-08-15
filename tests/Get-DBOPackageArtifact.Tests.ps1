Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\dbops.psd1" -Force
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}
$workFolder = Join-Path "$here\etc" "$commandName.Tests.dbops"
$packageName = Join-Path $workFolder 'TempDeployment.zip'
$scriptFolder = Join-Path $here 'etc\install-tests\success'
$v1scripts = Join-Path $scriptFolder '1.sql'
$v2scripts = Join-Path $scriptFolder '2.sql'
$v3scripts = Join-Path $scriptFolder '3.sql'
$projectPath = Join-Path $workFolder 'TempDeployment'

Describe "Get-DBOPackageArtifact tests" -Tag $commandName, UnitTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $projectPath -ItemType Directory -Force
        $null = New-Item $projectPath\Current -ItemType Directory -Force
        $null = New-Item $projectPath\Versions -ItemType Directory -Force
        $null = New-Item $projectPath\Versions\1.0 -ItemType Directory -Force
        $null = New-Item $projectPath\Versions\2.0 -ItemType Directory -Force
        $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force -ConfigurationFile "$here\etc\full_config.json"
        Copy-Item -Path $packageName -Destination $projectPath\Versions\1.0 
        $null = Add-DBOBuild -ScriptPath $v2scripts -Path $packageName -Build 2.0
        Copy-Item -Path $packageName -Destination $projectPath\Versions\2.0 
        $null = Add-DBOBuild -ScriptPath $v3scripts -Path $packageName -Build 3.0
        Copy-Item -Path $packageName -Destination $projectPath\Current
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
    }
    Context "Regular tests" {
        It "should return the last version of the artifact" {
            $result = Get-DBOPackageArtifact -Repository $workFolder -Name TempDeployment
            Get-DBOPackage $result | % Version | Should Be '3.0'
            $result.FullName | Should Be "$projectPath\Current\TempDeployment.zip"
        }
        It "should return the custom version of the artifact" {
            $result = Get-DBOPackageArtifact -Repository $workFolder -Name TempDeployment -Version 2.0
            Get-DBOPackage $result | % Version | Should Be '2.0'
            $result.FullName | Should Be "$projectPath\Versions\2.0\TempDeployment.zip"
        }
        It "should return the artifact when project folder is specified" {
            $result = Get-DBOPackageArtifact -Repository $projectPath -Name TempDeployment
            Get-DBOPackage $result | % Version | Should Be '3.0'
            $result.FullName | Should Be "$projectPath\Current\TempDeployment.zip"
        }
    }
    Context "Negative tests" {
        It "should throw when folder not found" {
            { Get-DBOPackageArtifact -Repository .\nonexistingpath -Name TempDeployment } | Should Throw
        }
        It "should throw when folder has improper structure" {
            { Get-DBOPackageArtifact -Repository $scriptFolder -Name TempDeployment } | Should Throw
        }
    }
}