function Set-DBODefaultSetting {
    <#
        .SYNOPSIS
            Sets configuration entries.
    
        .DESCRIPTION
            This function creates or changes configuration values.
            These can be used to provide dynamic configuration information outside the PowerShell variable system.
    
        .PARAMETER Name
            Name of the configuration entry.
    
        .PARAMETER Value
            The value to assign to the named configuration element.
    
        .PARAMETER Handler
            A scriptblock that is executed when a value is being set.
            Is only executed if the validation was successful (assuming there was a validation, of course)
    
        .PARAMETER Append
            Adds the value to the existing configuration instead of overwriting it
    
        .PARAMETER Temporary
            The setting is not persisted outside the current session.
            By default, settings will be remembered across all powershell sessions.

        .PARAMETER Scope
            Choose if the setting should be stored in current user's registry or will be shared between all users.
            Allowed values: CurrentUser, AllUsers.
            AllUsers will require administrative access to the computer (elevated session).

            Default: CurrentUser.
            
        .EXAMPLE
            Set-DBODefaultSetting -Name ConnectionTimeout -Value 5 -Temporary
        
            Change connection timeout setting for the current Powershell session to 5 seconds.
    
        .EXAMPLE
            Set-DBODefaultSetting -Name SchemaVersionTable -Value $null
        
            Change the default SchemaVersionTable setting to null, disabling the deployment logging by default
    #>
    [CmdletBinding(DefaultParameterSetName = "FullName")]
    param (
        [string]$Name,
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        $Value,
        [System.Management.Automation.ScriptBlock]$Handler,
        [switch]$Append,
        [switch]$Temporary,
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'CurrentUser'
    )

    process {
        if (-not (Get-DBODefaultSetting -Name $Name)) {
            Stop-PSFFunction -Message "Setting named $Name does not exist." -EnableException $true
        }
        
        $newValue = $Value
        if ($append) {
            $newValue += (Get-DBODefaultSetting -Name $Name -Value)
        }
               
        Set-PSFConfig -Module dbops -Name $Name -Value $newValue -EnableException

        $newScope = switch ($Scope) {
            'CurrentUser' { 'UserDefault' }
            'AllUsers' { 'SystemDefault' }
        }
        try {
            if (!$Temporary) { Register-PSFConfig -FullName dbops.$name -EnableException -WarningAction SilentlyContinue -Scope $newScope  }
        }
        catch {
            Set-PSFConfig -Module dbops -Name $name -Value ($Value -join ", ") -EnableException
            if (!$Temporary) { Register-PSFConfig -FullName dbops.$name -Scope $newScope -EnableException   }
        }
        Get-DBODefaultSetting -Name $Name 
    }
}