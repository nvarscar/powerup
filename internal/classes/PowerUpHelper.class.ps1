using namespace System.IO
using namespace System.IO.Compression

class PowerUpHelper {
	# Only keeps N last items in the path - helps to build relative paths
	static [string] SplitRelativePath ([string]$Path, [int]$Depth) {
		$returnPath = Split-Path -Path $Path -Leaf
		$parent = Split-Path -Path $Path -Parent
		while ($Depth-- -gt 0) {
			$returnPath = Join-Path -Path (Split-Path -Path $parent -Leaf) -ChildPath $returnPath
			$parent = Split-Path -Path $parent -Parent
		}
		return $returnPath
	}
	# Returns file contents as a binary array
	static [byte[]] GetBinaryFile ([string]$fileName) {
		$stream = [System.IO.File]::Open($fileName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
		$b = [byte[]]::new($stream.Length)
		try { $stream.Read($b, 0, $b.Length) }
		catch {	throw $_ }
		finally { $stream.Close() }
		return $b
	}
	# Converts a deflate stream into a memory stream - aka reads zip contents and writes them into memory
	static [System.IO.MemoryStream] ReadDeflateStream ([DeflateStream]$stream) {
		$memStream = [System.IO.MemoryStream]::new()
		$stream.CopyTo($memStream)
		$stream.Close()
		return $memStream
	}
	# Adds a new file entry into an opened ZipArchive object and fills it from the byte array
	static [void] WriteZipFile ([ZipArchive]$zipFile, [string]$fileName, [byte[]]$data) {
		#Remove old file entry if exists
		if ($zipFile.Mode -eq [ZipArchiveMode]::Update) {
			if ($oldEntry = $zipFile.GetEntry($fileName)) {
				$oldEntry.Delete()
			}
		}
		#Create new file entry
		$entry = $zipFile.CreateEntry($fileName)
		$writer = $entry.Open()
		#Write file contents
		$writer.Write($data, 0, $data.Length )
		#Close the stream
		$writer.Close()
	}
	# Adds a new file entry into an opened ZipArchive object and fills it from file stream object - not used for now
	# static [void] WriteZipFileStream ([ZipArchive]$zipFile, [string]$fileName, [FileStream]$stream) {
	# 	$entry = $zipFile.CreateEntry($fileName)
	# 	$writer = $entry.Open()
	# 	$data = [byte[]]::new(4098)
	# 	#Read from stream and write file contents
	# 	while ($read = $stream.Read($data, 0, $data.Length)) {
	# 		$writer.Write($data, 0, $data.Length )
	# 	}
	# 	#Close the stream
	# 	$writer.Close()
	# }
	# Returns an entry list from the archive file
	static [ZipArchiveEntry[]] GetArchiveItems ([string]$fileName) {
		$zip = [Zipfile]::OpenRead($FileName)
		try {
			$entries = $zip.Entries
		}
		catch { throw $_ }
		finally { $zip.Dispose() }
		return $entries
	}
	# Returns a specific entries from the archive file
	static [ZipArchiveEntry[]] GetArchiveItem ([string]$fileName, [string[]]$itemName) {
		$zip = [Zipfile]::OpenRead($FileName)
		try {
			$entries = $zip.Entries | Where-Object { $_.FullName -in $itemName}
		}
		catch { throw $_ }
		finally { $zip.Dispose() }
		return $entries
	}
	# Converts byte array to hash string
	static [string] ToHexString([byte[]]$InputObject) {
		$outString = "0x"
		$InputObject | ForEach-Object { $outString += ("{0:X}" -f $_).PadLeft(2, "0") }
		return $outString
	}
}