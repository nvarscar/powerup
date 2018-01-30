Function Remove-ArchiveItem {
	<#
	.SYNOPSIS
	Removes one or more items from the archive
	
	.DESCRIPTION
	Remove specific file or folder from the existing archive
	
	.PARAMETER Path
	Archive path
	
	.PARAMETER Item
	Archived item: file or folder
	
	.EXAMPLE
	Remove-ArchiveItem -Path c:\temp\myarchive.zip -Item MyFile.txt, Myfile2.txt
	
	.NOTES
	
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param(
		[Parameter(Mandatory = $true,
			Position = 1)]
		[string]$Path,
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			Position = 2)]
		[string[]]$Item
		# [switch]$Force,
		# [switch]$Recurse
	)
	begin {
		Function Remove-ArchiveItemRecurse {
			Param(
				[object]$Item,
				[object]$MoveTo
			)
			[int]$flags = 0
			$flags += 4     # no progress bar
			$flags += 16    # overwrite all
			$flags += 1024  # no UI in case of error
			
			if ($Item.IsFolder) {
				foreach ($subItem in $Item.GetFolder.Items()) {
					Remove-ArchiveItemRecurse $subItem $MoveTo
				}
			}
			$MoveTo.MoveHere($Item, $flags)
		}
		$shell = New-Object -ComObject Shell.Application
	}
	process {
		foreach ($currentItem in $Item) {
			#Get parent folder inside the archive
			$shellParent = $shell.NameSpace((Split-Path (Join-Path (Resolve-Path $Path) $currentItem) -Parent))

			# get archive item
			if ($shellItem = $shellParent.Items() | Where-Object Name -eq (Split-Path $currentItem -Leaf)) {
				if ($pscmdlet.ShouldProcess($currentItem, "Remove archive item")) {
					$workFolder = New-TempWorkspaceFolder
					try {
						Remove-ArchiveItemRecurse -Item $shellItem -MoveTo $shell.NameSpace($workFolder.FullName)
					}
					catch {
						throw $_
					}
					finally {
						if ($workFolder.Name -like 'PowerUpWorkspace*') {
							Remove-Item $workFolder -Recurse -Force
						}
					}
				}
			}
			else {
				Write-Warning -Message "Item $currentItem was not found in $Path"
			}
		}
	}
	end {

	}
}