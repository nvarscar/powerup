Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($class in (Get-Item $PSScriptRoot\classes\*.ps1)) {
	. $class.FullName
}
foreach ($function in (Get-Item $PSScriptRoot\functions\*.ps1)) {
	. $function.FullName
}