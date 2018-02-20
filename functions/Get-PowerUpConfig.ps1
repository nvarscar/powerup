function Get-PowerUpConfig {
	[CmdletBinding()]
	param
	(
		[string]$Path
	)
	if ($Path) {
		[PowerUpConfig]::FromFile($Path)
	}
	else {
		[PowerUpConfig]::new()
	}
}