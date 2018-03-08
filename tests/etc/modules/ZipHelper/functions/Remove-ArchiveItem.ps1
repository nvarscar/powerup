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
		#Open new file stream
		$writeMode = [System.IO.FileMode]::Open
		$stream = [FileStream]::new((Resolve-Path $Path), $writeMode)
		try {
			#Open zip file
			$zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
			try {
				#Write files
				foreach ($currentItem in $itemCollection) {
					if ($e = $zip.GetEntry($currentItem)) {
						$e.Delete()
					}
				}
				
			}
			catch { throw $_ }
			finally { $zip.Dispose() }	
		}
		catch { throw $_ }
		finally { $stream.Dispose()	}
	}
}