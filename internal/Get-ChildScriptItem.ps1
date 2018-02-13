function Get-ChildScriptItem {
	[CmdletBinding()]
	Param (
		[string]$Path
	)
	Function Get-ChildItemDepth ([System.IO.FileSystemInfo]$Item, [int]$Depth = 0) {
		Write-Debug "Getting child items from $Item with current depth $Depth"
		foreach ($childItem in (Get-ChildItem $Item)) {
			if ($childItem.PSIsContainer) {
				Get-ChildItemDepth -Item (Get-Item $childItem.FullName) -Depth ($Depth + 1)
			}
			else {
				Add-Member -InputObject $childItem -MemberType NoteProperty -Name Depth -Value $Depth -PassThru
			}
		}
	}
	foreach ($currentItem in (Get-Item $Path)) {
		Get-ChildItemDepth $currentItem
	}
}