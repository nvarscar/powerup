Function Add-ArchiveItem {
	<#
	.SYNOPSIS
	Adds one or more items to the archive
	
	.DESCRIPTION
	Adds specific file or folder to the existing archive
	
	.PARAMETER Path
	Archive path
	
	.PARAMETER Item
	Archived item: file or folder
	
	.EXAMPLE
	Add-ArchiveItem -Path c:\temp\myarchive.zip -Item MyFile.txt, Myfile2.txt -InnerFolder inner_folder\path
	
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
		[string[]]$Item,
		[string]$InnerFolder = '.'
		# [switch]$Force,
		# [switch]$Recurse
	)
	begin {
		if (!(Test-Path $Path)) {
			throw "Path not found: $Path"	
		}
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

			#Create inner folder if needed
			$innerFolderPath = Join-Path $workFolder $InnerFolder
			if (!(Test-Path $innerFolderPath)) {
				$null = New-Item -Path $innerFolderPath -ItemType Directory
			}

			#Add items
			foreach ($currentItem in $itemCollection) {
				If (Test-Path $currentItem) {
					Copy-Item $currentItem $innerFolderPath
				}
				else {
					Write-Warning -Message "Item $currentItem was not found"
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