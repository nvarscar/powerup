function Get-ChildScriptItem ($Path) {
		foreach ($currentItem in (Get-Item $Path)) {
			if ($currentItem.PSIsContainer) {
				$replacePath = $currentItem.FullName
			}
			else {
				$replacePath = $currentItem.DirectoryName
			}
			$items = Get-ChildItem $currentItem -Recurse -File
			foreach ($i in $items) {
				$obj = @{ } | Select-Object FullName, ReplacePath
				$obj.FullName = $i.FullName
				$obj.ReplacePath = $replacePath
				$obj
			}
		}
}