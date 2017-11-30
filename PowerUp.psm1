Get-ChildItem -Path "$PSScriptRoot\bin\*.dll" -Recurse | Unblock-File -ErrorAction SilentlyContinue

foreach ($assembly in (Get-ChildItem -Path "$PSScriptRoot\bin\*.dll")) {
	Add-Type -Path $assembly.FullName
}


foreach ($function in (Get-ChildItem "$PSScriptRoot\internal\*.ps1")) {
	. $function.FullName
}

foreach ($function in (Get-ChildItem "$PSScriptRoot\functions\*.ps1")) {
	. $function.FullName
}





