function Get-ArchiveItem {
	param ([Parameter(Mandatory)]
		[string]$Archive)
	function recurse-items {
		param ([object]$items)
		
		foreach ($item in $items) {
			$item
			$folder = $item.GetFolder
			if ($folder) {
				recurse-items $folder.Items()
			}
		}
	}
	
	$Archive = Resolve-Path $Archive
	$shellApp = New-Object -ComObject shell.application
	$zipFile = $shellApp.NameSpace($Archive)
	recurse-items $zipFile.Items() | ForEach-Object {
		$zipPath = $_.Path.Replace($Archive + [System.IO.Path]::DirectorySeparatorChar, '')
		$level = ($zipPath.Split([string][System.IO.Path]::DirectorySeparatorChar)).Count
		$_ | Add-Member @{ Archive = $Archive; Level = $level; Path = $zipPath } -PassThru -Force
	} | Sort-Object Level, Name | Select-Object * -ExcludeProperty Application, Parent, GetLink, GetFolder, Level
}