Function Get-NewBuildNumber {
	<#
	.SYNOPSIS
	Returns a new build number based on current date/time
	
	.DESCRIPTION
	Uses current date/time to generate a dot-separated string in the format: yyyy.mm.dd.hhmmss. This string is to be used as an internal build number when build hasn't been specified explicitly.
	
	.EXAMPLE
	$string = Get-NewBuildNumber
	
	.NOTES
	
	#>
	Param ()
	[string]$currentDate.Year + '.' + [string]$currentDate.Month + '.' + [string]$currentDate.Day + '.' + [string]$currentDate.Hour + [string]$currentDate.Minute + [string]$currentDate.Second
}