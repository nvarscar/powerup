# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
    # run on scenario MSSQL
    "MSSQL" = @(
        'Install-PowerUpPackage',
		'Add-PowerUpBuild',
		'Get-PowerUpConfig',
		'New-PowerUpPackage',
		'Remove-PowerUpBuild',
		'Get-PowerUpPackage',
		'Update-PowerUpConfig'
    )
    # do not run everywhere
    "disabled" = @()
}