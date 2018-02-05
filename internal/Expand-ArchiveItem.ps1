Function Expand-ArchiveItem {
	<#
	.SYNOPSIS
	Extracts one or more items from the archive
	
	.DESCRIPTION
	Extract specific file or folder from the existing archive
	
	.PARAMETER Path
	Archive path
	
	.PARAMETER DestinationPath
	Destination folder to put the item into
	
	.PARAMETER Item
	Archived item: file or folder
	
	.PARAMETER PassThru
	If specified, returns the unpacked item object
	
	.EXAMPLE
	Expand-ArchiveItem -Path c:\temp\myarchive.zip -DestinationPath c:\MyFolder -Item MyFile.txt, Myfile2.txt
	
	.NOTES
	General notes
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param(
		[Parameter(Mandatory = $true,
			Position = 1)]
		[string]$Path,
		[Parameter(Mandatory = $true,
			Position = 2)]
		[string]$DestinationPath,
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			Position = 3)]
		[string[]]$Item,
		[switch]$PassThru,
		[switch]$Force,
		[switch]$Recurse
	)
	begin {
		$shell = New-Object -ComObject Shell.Application
	}
	process {
		foreach ($currentItem in $Item) {
			#Get parent folder inside the archive
			$shellParent = $shell.NameSpace((Split-Path (Join-Path (Resolve-Path $Path) $currentItem) -Parent))

			# get archive item
			if ($shellItem = $shellParent.Items() | Where-Object Name -eq (Split-Path $currentItem -Leaf)) {

				# check if item exists
				$itemDestPath = Join-Path $DestinationPath $currentItem
				if ($Force -eq $false -and (Test-Path $itemDestPath)) {
					Write-Warning -Message "Destination item $itemDestPath already exists. No action performed. Use -Force to overwrite."
					continue
				}
				
				# create parent directory
				$parent = Split-Path $itemDestPath -Parent
				if (!(Test-Path $parent)) {
					if ($pscmdlet.ShouldProcess($parent, "Creating parent directory")) {
						$null = New-Item -Path $parent -ItemType Directory
					}
				}

				# unzip item
				[int]$flags = 0
				$flags += 4     # no progress bar
				$flags += 16    # overwrite all
				$flags += 1024  # no UI in case of error
				if (!$Recurse) {
					$flags += 4096  # do not include subdirectories 
				}

				if ($pscmdlet.ShouldProcess($currentItem, "Extract archive item")) {
					$shell.NameSpace($parent).CopyHere($shellItem, $flags)
				}

				# return item object
				if ($PassThru) {
					Get-Item (Join-Path $DestinationPath $currentItem)
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