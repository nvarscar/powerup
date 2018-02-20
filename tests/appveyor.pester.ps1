<#
.SYNOPSIS
This script will invoke Pester tests, then serialize XML results and pull them in appveyor.yml

.DESCRIPTION
Internal function that creates SMO server object.

.PARAMETER Finalize
If Finalize is specified, we collect XML output, upload tests, and indicate build errors

.PARAMETER PSVersion
The version of PS

.PARAMETER TestFile
The output file

.PARAMETER ProjectRoot
The appveyor project root

.PARAMETER ModuleBase
The location of the module

.PARAMETER IncludeCoverage
Calculates coverage and sends it to codecov.io

.EXAMPLE
.\appveyor.pester.ps1
Executes the test

.EXAMPLE
.\appveyor.pester.ps1 -Finalize
Finalizes the tests
#>
param (
    [switch]$Finalize,
    $PSVersion = $PSVersionTable.PSVersion.Major,
    $TestFile = "TestResultsPS$PSVersion.xml",
    $ProjectRoot = $ENV:APPVEYOR_BUILD_FOLDER,
    $ModuleBase = $ProjectRoot,
    [switch]$IncludeCoverage
)

# Move to the project root
Set-Location $ModuleBase
#removes previously imported module, if any
Remove-Module powerup -ErrorAction Ignore
#imports the psm1 to be able to use internal functions in tests
#Import-Module "$ModuleBase\powerup.psm1"
#imports the module making sure DLL is loaded ok
Import-Module "$ModuleBase\powerup.psd1"


function Get-CoverageIndications($Path, $ModuleBase) {
    # takes a test file path and figures out what to analyze for coverage (i.e. dependencies)
    $CBHRex = [regex]'(?smi)<#(.*)#>'
    $everything = (Get-Module dbatools).ExportedCommands.Values
    $everyfunction = $everything.Name
    $funcs = @()
    $leaf = Split-Path $path -Leaf
    # assuming Get-DbaFoo.Tests.ps1 wants coverage for "Get-DbaFoo"
    # but allowing also Get-DbaFoo.one.Tests.ps1 and Get-DbaFoo.two.Tests.ps1
    $func_name += ($leaf -replace '^([^.]+)(.+)?.Tests.ps1', '$1')
    if ($func_name -in $everyfunction) {
        $funcs += $func_name
        $f = $everything | Where-Object Name -eq $func_name
        $source = $f.Definition
        $CBH = $CBHRex.match($source).Value
        $cmdonly = $source.Replace($CBH, '')
        foreach ($e in $everyfunction) {
            # hacky, I know, but every occurrence of any function plus a space kinda denotes usage !?
            $searchme = "$e "
            if ($cmdonly.contains($searchme)) {
                $funcs += $e
            }
        }
    }
    $testpaths = @()
    $allfiles = Get-ChildItem -File -Path "$ModuleBase\internal", "$ModuleBase\functions" -Filter '*.ps1'
    foreach ($f in $funcs) {
        # exclude always used functions ?!
        if ($f -in ('Connect-SqlInstance', 'Select-DefaultView', 'Stop-Function', 'Write-Message')) { continue }
        # can I find a correspondence to a physical file (again, on the convenience of having Get-DbaFoo.ps1 actually defining Get-DbaFoo)?
        $res = $allfiles | Where-Object { $_.Name.Replace('.ps1', '') -eq $f }
        if ($res.count -gt 0) {
            $testpaths += $res.FullName
        }
    }
    return @() + ($testpaths | Select-Object -Unique)
}

function Get-CodecovReport($Results, $ModuleBase) {
    #handle coverage https://docs.codecov.io/reference#upload
    $report = @{'coverage' = @{}}
    #needs correct casing to do the replace
    $ModuleBase = (Resolve-Path $ModuleBase).Path
    # things we wanna a report for (and later backfill if not tested)
    $allfiles = Get-ChildItem -File -Path "$ModuleBase\internal", "$ModuleBase\functions" -Filter '*.ps1'

    $missed = $results.CodeCoverage | Select-Object -ExpandProperty MissedCommands | Sort-Object -Property File, Line -Unique
    $hits = $results.CodeCoverage | Select-Object -ExpandProperty HitCommands | Sort-Object -Property File, Line -Unique
    $LineCount = @{}
    $hits | ForEach-Object {
        $filename = $_.File.Replace("$ModuleBase\", '').Replace('\', '/')
        if ($filename -notin $report['coverage'].Keys) {
            $report['coverage'][$filename] = @{}
            $LineCount[$filename] = (Get-Content $_.File -Raw | Measure-Object -Line).Lines
        }
        $report['coverage'][$filename][$_.Line] = 1
    }

    $missed | ForEach-Object {
        $filename = $_.File.Replace("$ModuleBase\", '').Replace('\', '/')
        if ($filename -notin $report['coverage'].Keys) {
            $report['coverage'][$filename] = @{}
            $LineCount[$filename] = (Get-Content $_.File | Measure-Object -Line).Lines
        }
        if ($_.Line -notin $report['coverage'][$filename].Keys) {
            #miss only if not already covered
            $report['coverage'][$filename][$_.Line] = 0
        }
    }

    $newreport = @{'coverage' = [ordered]@{}}
    foreach ($fname in $report['coverage'].Keys) {
        $Linecoverage = [ordered]@{}
        for ($i = 1; $i -le $LineCount[$fname]; $i++) {
            if ($i -in $report['coverage'][$fname].Keys) {
                $Linecoverage["$i"] = $report['coverage'][$fname][$i]
            }
        }
        $newreport['coverage'][$fname] = $Linecoverage
    }

    #backfill it
    foreach ($target in $allfiles) {
        $target_relative = $target.FullName.Replace("$ModuleBase\", '').Replace('\', '/')
        if ($target_relative -notin $newreport['coverage'].Keys) {
            $newreport['coverage'][$target_relative] = @{"1" = $null}
        }
    }
    $newreport
}

function Send-CodecovReport($CodecovReport) {
    $params = @{}
    $params['branch'] = $env:APPVEYOR_REPO_BRANCH
    $params['service'] = "appveyor"
    $params['job'] = $env:APPVEYOR_ACCOUNT_NAME
    if ($params['job']) { $params['job'] += '/' + $env:APPVEYOR_PROJECT_SLUG }
    if ($params['job']) { $params['job'] += '/' + $env:APPVEYOR_BUILD_VERSION }
    $params['build'] = $env:APPVEYOR_JOB_ID
    $params['pr'] = $env:APPVEYOR_PULL_REQUEST_NUMBER
    $params['slug'] = $env:APPVEYOR_REPO_NAME
    $params['commit'] = $env:APPVEYOR_REPO_COMMIT
    Add-Type -AssemblyName System.Web
    $CodeCovParams = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    $params.GetEnumerator() | Where-Object Value | ForEach-Object { $CodeCovParams.Add($_.Name, $_.Value) }
    $Request = [System.UriBuilder]('https://codecov.io/upload/v2')
    $Request.Query = $CodeCovParams.ToString()
    Invoke-RestMethod -Uri $Request.Uri -Method Post -InFile $CodecovReport -ContentType 'multipart/form-data'
}

if (-not $Finalize) {
	# Welcome message
	Write-Host -ForegroundColor DarkGreen "Running PowerUp build $((Get-Module PowerUp).Version.ToString()) on PS $($PSVersionTable.PsVersion.ToString())"
	# Invoke pester.groups.ps1 to know which tests to run
	. "$ModuleBase\tests\pester.groups.ps1"

	# retrieve all .Tests.
	$AllTestsFiles = Get-ChildItem -File -Path "$ModuleBase\tests\*.Tests.ps1"
	# exclude "disabled"
	$AllTests = $AllTestsFiles | Where-Object { ($_.Name -replace '^([^.]+)(.+)?.Tests.ps1', '$1') -notin $TestsRunGroups['disabled'] }

	# do we have a scenario ?
	if ($env:SCENARIO) {
		# if so, do we have a group with tests to run ?
		if ($env:SCENARIO -in $TestsRunGroups.Keys) {
			$AllScenarioTests = $AllTests | Where-Object { ($_.Name -replace '\.Tests\.ps1$', '') -in $TestsRunGroups[$env:SCENARIO] }
		}
		else {
			$AllScenarioTests = $AllTests
		}
	}
	else {
		$AllScenarioTests = $AllTests
	}

	if ($AllTests.Count -eq 0 -and $AllScenarioTests.Count -eq 0) {
		throw "something went wrong, nothing to test"
	}
}

#Run a test with the current version of PowerShell
#Make things faster by removing most output
if (-not $Finalize) {
    Import-Module Pester
    Set-Variable ProgressPreference -Value SilentlyContinue
    if ($AllScenarioTests.Count -eq 0) {
        Write-Host -ForegroundColor DarkGreen "Nothing to do in this scenario"
        return
    }
    # invoking a single invoke-pester consumes too much memory, let's go file by file
    $AllTestsWithinScenario = Get-ChildItem -File -Path $AllScenarioTests
    $Counter = 0
    foreach ($f in $AllTestsWithinScenario) {
        $Counter += 1
        $PesterSplat = @{
            'Script'   = $f.FullName
            'Show'     = 'None'
            'PassThru' = $true
        }
        #opt-in
        if ($IncludeCoverage) {
            $CoverFiles = Get-CoverageIndications -Path $f -ModuleBase $ModuleBase
            $PesterSplat['CodeCoverage'] = $CoverFiles
            $PesterSplat['CodeCoverageOutputFile'] = "$ModuleBase\PesterCoverage$Counter.xml"
        }
        # Pester 4.0 outputs already what file is being ran. If we remove write-host from every test, we can time
        # executions for each test script (i.e. Executing Get-DbaFoo .... Done (40 seconds))
        Invoke-Pester @PesterSplat | Export-Clixml -Path "$ModuleBase\PesterResults$PSVersion$Counter.xml"
    }
}
else {
    #What failed? How many tests did we run ?
    $results = @(Get-ChildItem -Path "$ModuleBase\PesterResults*.xml" | Import-Clixml)
    #$totalcount = $results | Select-Object -ExpandProperty TotalCount | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $failedcount = $results | Select-Object -ExpandProperty FailedCount | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    if ($failedcount -gt 0) {
        $faileditems = $results | Select-Object -ExpandProperty TestResult | Where-Object { $_.Passed -notlike $True }
        if ($faileditems) {
            Write-Warning "Failed tests summary:"
            $faileditems | ForEach-Object {
                $name = $_.Name
                [pscustomobject]@{
                    Describe = $_.Describe
                    Context  = $_.Context
                    Name     = "It $name"
                    Result   = $_.Result
                    Message  = $_.FailureMessage
                }
            } | Sort-Object Describe, Context, Name, Result, Message | Format-List
            throw "$failedcount tests failed."
        }
    }
    #opt-in
    if ($IncludeCoverage) {
        $CodecovReport = Get-CodecovReport -Results $results -ModuleBase $ModuleBase
        $CodecovReport | ConvertTo-Json -Depth 4 -Compress | Out-File -FilePath "$ModuleBase\PesterResultsCoverage.json" -Encoding utf8
    }
}