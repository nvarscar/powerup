Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$moduleCatalog = Get-Content "$PSScriptRoot\internal\json\dbops.json" -Raw | ConvertFrom-Json
foreach ($bin in $moduleCatalog.Libraries) {
	Unblock-File -Path "$PSScriptRoot\$bin" -ErrorAction SilentlyContinue
	Add-Type -Path "$PSScriptRoot\$bin"
}

foreach ($function in $moduleCatalog.Functions) {
	. "$PSScriptRoot\$function"
}

foreach ($function in $moduleCatalog.Internal) {
	. "$PSScriptRoot\$function"
}

