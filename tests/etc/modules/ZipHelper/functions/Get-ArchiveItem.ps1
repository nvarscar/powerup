function Get-ArchiveItem {
	<#
	.SYNOPSIS
	Returns archive items from the archive file
	
	.DESCRIPTION
	Returns a list of archive files from the archive. Returns item contents as a byte array when specific items are provided.
	
	.PARAMETER Path
	Archive Path
	
	.PARAMETER Item
	Path to existing items inside the archive
	
	.EXAMPLE
	# Return an archive file list
	Get-ArchiveItem .\asd.zip 
	
	.EXAMPLE
	# Return an archive file with binary contents
	Get-ArchiveItem .\asd.zip asd\file1.txt
	
	.NOTES
	General notes
	#>
	param ([Parameter(Mandatory)]
		[string]$Path,
		[string[]]$Item
	)
	if ($Item) {
		$result = [ZipHelper]::GetArchiveItem((Resolve-Path $Path), $Item) 
	}
	else {
		$result = [ZipHelper]::GetArchiveItems((Resolve-Path $Path))
	}
	$result | Add-Member -MemberType AliasProperty -Name Path -Value FullName -PassThru | `
		Add-Member -MemberType AliasProperty -Name Size -Value Length -PassThru 
}