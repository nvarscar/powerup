Function Get-VariableTokens {
	#Get #{tokens} from the string
	Param (
		[string]$InputString
	)
	[regex]::matches($InputString, "\#\{([a-zA-Z0-9.]*)\}") | ForEach-Object { $_.Groups[1].Value }
}