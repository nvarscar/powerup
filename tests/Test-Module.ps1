<#
	.SYNOPSIS
		A brief description of the Test-Module.ps1 file.
	
	.DESCRIPTION
		The Test-Module.ps1 script lets you test the functions and other features of
		your module in your PowerShell Studio module project. It's part of your project,
		but it is not included in your module.
		
		In this test script, import the module (be careful to import the correct version)
		and write commands that test the module features. You can include Pester
		tests, too.
		
		To run the script, click Run or Run in Console. Or, when working on any file
		in the project, click Home\Run or Home\Run in Console, or in the Project pane,
		right-click the project name, and then click Run Project.
	
	.PARAMETER Path
		A description of the Path parameter.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2017 v5.4.145
		Created on:   	11/21/2017 1:11 PM
		Created by:   	kkravtsov
		Organization:
		Filename:     	Test-Module.ps1
		===========================================================================
#>
param
(
	[string[]]$Path = '.',
	[string[]]$Tag
	
)

#Explicitly import the module for testing
Import-Module "$here\..\PowerUp.psd1" -Force

#Run each module function
$params = @{
	Script = @{
		Path = $Path
		Parameters = @{
			Batch = $true
		}
	}
}
if ($Tag) {
	$params += @{ Tag = $Tag}
}
Invoke-Pester @params

#Sample Pester Test
#Describe "Test PowerUp" {
#	It "tests Write-HellowWorld" {
#		Write-HelloWorld | Should BeExactly "Hello World"
#	}	
#}