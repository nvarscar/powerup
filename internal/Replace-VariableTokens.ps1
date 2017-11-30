Function Replace-VariableTokens {
	#Replaces all the tokens with known variables (-Variables or $OctopusParameters)
	[CmdletBinding()]
	Param (
		$InputString,
		$RuntimeVariables
	)
	Write-Debug "Processing string: $($InputString)"
	foreach ($token in (Get-VariableTokens $InputString)) {
		Write-Debug "Processing token: $token"
		#Replace variables found in the config
		$tokenRegEx = "\#\{$token\}"
		if ($RuntimeVariables -and $property -ne 'Variables') {
			if (
				($RuntimeVariables.GetType() -eq [hashtable] -and $RuntimeVariables.Keys -contains $token) -or
				($RuntimeVariables.GetType() -eq [PSCustomObject] -and $RuntimeVariables.psobject.Properties.Name -contains $token)
			) {
				$InputString = $InputString -replace $tokenRegEx, $RuntimeVariables.$token
			}
		}
		#Replace Octopus variables
		if ($OctopusParameters -and $OctopusParameters.Keys -contains $token) {
			$InputString = $InputString -replace $tokenRegEx, $OctopusParameters[$token]
		}
		Write-Debug "String after replace: $($InputString)"
	}
	$InputString
}