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
		$itemCollection = @()
	}
	process {
		foreach ($currentItem in $Item) {
			$itemCollection += $currentItem
		}
	}
	end {
		$workFolder = New-TempWorkspaceFolder
		try {
			#Extract package
			Write-Verbose "Extracting archive $Path to $workFolder"
			Expand-Archive -Path $Path -DestinationPath $workFolder

			#Remove items
			foreach ($currentItem in $itemCollection) {
				$currentItemPath = Join-Path $workFolder $currentItem
				If (Test-Path $currentItemPath) {
					Remove-Item $currentItemPath -Recurse -Force
				}
				else {
					Write-Warning -Message "Item $currentItem was not found in $Path"
				}
			}

			#Re-compress archive
			Write-Verbose "Repackaging original archive $Path"
			Compress-Archive "$workFolder\*" -DestinationPath $Path -Force
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