Function Resolve-VariableToken {
	<#
	.SYNOPSIS
	Replaces all the tokens in a string with provided variables
	
	.DESCRIPTION
	Parses input string and replaces all the #{tokens} inside it with provided variables
	
	.PARAMETER InputString
	String to parse
	
	.PARAMETER Runtime
	Variables collection. Token names should match keys in the hashtable
	
	.EXAMPLE
	Resolve-VariableToken -InputString "SELECT '#{foo}' as str" -Runtime @{ foo = 'bar'}
	#>
	[CmdletBinding()]
	Param (
		[string[]]$InputString,
		[hashtable]$Runtime
	)
	foreach ($str in $InputString) {
		Write-Debug "Processing string: $str"
		foreach ($token in (Get-VariableTokens $str)) {
			Write-Debug "Processing token: $token"
			#Replace variables found in the config
			$tokenRegEx = "\#\{$token\}"
			if ($Runtime) {
				if ($Runtime.Keys -contains $token) {
					$str = $str -replace $tokenRegEx, $Runtime.$token
				}
			}
			Write-Debug "String after replace: $str"
		}
		$str
	}
}