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
	# Put two txt files into archive.zip\inner_folder\path\
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
			$itemCollection += Get-Item $currentItem
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
					$fileName = Split-Path $currentItem -Leaf
					$innerPath = (Join-Path $InnerFolder $fileName).TrimStart('.\')
					[ZipHelper]::WriteZipFile($zip, $innerPath, [ZipHelper]::GetBinaryFile($currentItem.FullName))
				}
				
			}
			catch { throw $_ }
			finally { $zip.Dispose() }	
		}
		catch { throw $_ }
		finally { $stream.Dispose()	}
		
	}
}