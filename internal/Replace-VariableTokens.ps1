Function Replace-VariableTokens {
	#Replaces all the tokens with provided variables
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