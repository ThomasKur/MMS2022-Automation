<#
.DESCRIPTION
Disables exchange Online Powershell capabilites for users which are not members of specific groups or Azure AD roles to reduce the attack surface. 

The Service Principal(RunAs) of the Azure Automation Workspace requires:
 - MSGraph
   - Group.Read.All
   - GroupMember.ReadWrite.All
   - RoleManagement.Read.Directory
   - User.ReadWrite.All
- Office 365 Exchange Online
   - Exchange.ManageAsApp

Additionally, the service principal needs to get the the "Exchange Administrator" role assigned in Azure AD.


.EXAMPLE
    .\Disable-PowerShellAccessExoForNonAdmins.ps1

.NOTES
Author: Thomas Kurth/baseVISION
Date:   29.10.2021

History
    001: First Version

ExitCodes:
    0: Successfull
#>

[CmdletBinding()]
Param()

## Manual Variable Definition
########################################################
$tenant = "kurcontoso.onmicrosoft.com" # Name of the tenant
$ExceptionGroups = @("b8fe869d-ff0a-4427-80dd-7c141db3d69c") # Id of groups, members of them will be able to use Exchange PowerShell.
$ExceptionRoles = @("Exchange Administrator","Global Administrator","Security Administrator","Security Reader") # Names of Azure AD roles, members of them will be able to use Exchange PowerShell.

$DebugPreference = "Continue"
$ScriptVersion = "001"
$ScriptName = "Disable-PowerShellAccessExoForNonAdmins"

$LogFilePathFolder = "C:\Windows\Logs"
$FallbackScriptPath = "C:\Windows" # This is only used if the filename could not be resolved(IE running in ISE)

# Log Configuration
$DefaultLogOutputMode = "Console-LogFile" # "Console-LogFile","Console-WindowsEvent","LogFile-WindowsEvent","Console","LogFile","WindowsEvent","All"
$DefaultLogWindowsEventSource = $ScriptName
$DefaultLogWindowsEventLog = "CustomPS"
 
#region Functions
########################################################

function Write-Log {
    <#
    .DESCRIPTION
    Write text to a logfile with the current time.

    .PARAMETER Message
    Specifies the message to log.

    .PARAMETER Type
    Type of Message ("Info","Debug","Warn","Error").

    .PARAMETER OutputMode
    Specifies where the log should be written. Possible values are "Console","LogFile" and "Both".

    .PARAMETER Exception
    You can write an exception object to the log file if there was an exception.

    .EXAMPLE
    Write-Log -Message "Start process XY"

    .NOTES
    This function should be used to log information to console or log file.
    #>
    param(
        [Parameter(Mandatory = $true, Position = 1)]
        [String]
        $Message
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Debug", "Warn", "Error")]
        [String]
        $Type = "Debug"
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Console-LogFile", "Console-WindowsEvent", "LogFile-WindowsEvent", "Console", "LogFile", "WindowsEvent", "All")]
        [String]
        $OutputMode = $DefaultLogOutputMode
        ,
        [Parameter(Mandatory = $false)]
        [Exception]
        $Exception
    )
    
    $DateTimeString = Get-Date -Format "yyyy-MM-dd HH:mm:sszz"
    $Output = ($DateTimeString + "`t" + $Type.ToUpper() + "`t" + $Message)
    if ($Exception) {
        $ExceptionString = ("[" + $Exception.GetType().FullName + "] " + $Exception.Message)
        $Output = "$Output - $ExceptionString"
    }

    if ($OutputMode -eq "Console" -OR $OutputMode -eq "Console-LogFile" -OR $OutputMode -eq "Console-WindowsEvent" -OR $OutputMode -eq "All") {
        if ($Type -eq "Error") {
            Write-Error $output
        }
        elseif ($Type -eq "Warn") {
            Write-Warning $output
        }
        elseif ($Type -eq "Debug") {
            Write-Debug $output
        }
        else {
            Write-Verbose $output -Verbose
        }
    }
    
    if ($OutputMode -eq "LogFile" -OR $OutputMode -eq "Console-LogFile" -OR $OutputMode -eq "LogFile-WindowsEvent" -OR $OutputMode -eq "All") {
        try {
            Add-Content $LogFilePath -Value $Output -ErrorAction Stop
        }
        catch {
            exit 99001
        }
    }

    if ($OutputMode -eq "Console-WindowsEvent" -OR $OutputMode -eq "WindowsEvent" -OR $OutputMode -eq "LogFile-WindowsEvent" -OR $OutputMode -eq "All") {
        try {
            New-EventLog -LogName $DefaultLogWindowsEventLog -Source $DefaultLogWindowsEventSource -ErrorAction SilentlyContinue
            switch ($Type) {
                "Warn" {
                    $EventType = "Warning"
                    break
                }
                "Error" {
                    $EventType = "Error"
                    break
                }
                default {
                    $EventType = "Information"
                }
            }
            Write-EventLog -LogName $DefaultLogWindowsEventLog -Source $DefaultLogWindowsEventSource -EntryType $EventType -EventId 1 -Message $Output -ErrorAction Stop
        }
        catch {
            exit 99002
        }
    }
}

function New-Folder {
    <#
    .DESCRIPTION
    Creates a Folder if it's not existing.

    .PARAMETER Path
    Specifies the path of the new folder.

    .EXAMPLE
    CreateFolder "c:\temp"

    .NOTES
    This function creates a folder if doesn't exist.
    #>
    param(
        [Parameter(Mandatory = $True, Position = 1)]
        [string]$Path
    )
    # Check if the folder Exists

    if (Test-Path $Path) {
        Write-Log "Folder: $Path Already Exists"
    }
    else {
        New-Item -Path $Path -type directory | Out-Null
        Write-Log "Creating $Path"
    }
}

function Set-RegValue {
    <#
    .DESCRIPTION
    Set registry value and create parent key if it is not existing.

    .PARAMETER Path
    Registry Path

    .PARAMETER Name
    Name of the Value

    .PARAMETER Value
    Value to set

    .PARAMETER Type
    Type = Binary, DWord, ExpandString, MultiString, String or QWord

    #>
    param(
        [Parameter(Mandatory = $True)]
        [string]$Path,
        [Parameter(Mandatory = $True)]
        [string]$Name,
        [Parameter(Mandatory = $True)]
        [AllowEmptyString()]
        [string]$Value,
        [Parameter(Mandatory = $True)]
        [string]$Type
    )
    
    try {
        $ErrorActionPreference = 'Stop' # convert all errors to terminating errors
        Start-Transaction

        if (Test-Path $Path -erroraction silentlycontinue) {      
 
        }
        else {
            New-Item -Path $Path -Force
            Write-Log "Registry key $Path created"  
        } 
        $null = New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force
        Write-Log "Registry Value $Path, $Name, $Type, $Value set"
        Complete-Transaction
    }
    catch {
        Undo-Transaction
        Write-Log "Registry value not set $Path, $Name, $Value, $Type" -Type Error -Exception $_.Exception
    }
}

#endregion

#region Dynamic Variables and Parameters
########################################################

# Try get actual ScriptName
try {
    $CurrentFileNameTemp = $MyInvocation.MyCommand.Name
    If ($null -eq $CurrentFileNameTemp -or $CurrentFileNameTemp -eq "") {
        $CurrentFileName = "NotExecutedAsScript"
    }
    else {
        $CurrentFileName = $CurrentFileNameTemp
    }
}
catch {
    $CurrentFileName = $LogFilePathScriptName
}
$LogFilePath = "$LogFilePathFolder\{0}_{1}_{2}.log" -f ($ScriptName -replace ".ps1", ''), $ScriptVersion, (Get-Date -uformat %Y%m%d%H%M)
# Try get actual ScriptPath
try {
    try { 
        $ScriptPathTemp = Split-Path $MyInvocation.MyCommand.Path
    }
    catch {

    }
    if ([String]::IsNullOrWhiteSpace($ScriptPathTemp)) {
        $ScriptPathTemp = Split-Path $MyInvocation.InvocationName
    }

    If ([String]::IsNullOrWhiteSpace($ScriptPathTemp)) {
        $ScriptPath = $FallbackScriptPath
    }
    else {
        $ScriptPath = $ScriptPathTemp
    }
}
catch {
    $ScriptPath = $FallbackScriptPath
}

#endregion

#region Initialization
########################################################

if (!(Test-Path $LogFilePathFolder))
{
    New-Folder $LogFilePathFolder
}

Write-Log "Start Script $Scriptname"


Write-log -Type Info -message "Check Module"
$Module = Get-Module -Name ExchangeOnlineManagement -ListAvailable

If ($Null -eq $Module){
    Write-log -Type Info -message "ExchangeOnlineManagement Module not installed"
} else {
    Write-log -Type Info -message "ExchangeOnlineManagement Module found"
}

$connection = Get-AutomationConnection –Name AzureRunAsConnection

Write-log -Type Info -message "Connecting to Exchange Online ..."


Connect-ExchangeOnline –CertificateThumbprint $connection.CertificateThumbprint –AppId $connection.ApplicationID -ShowBanner:$false –Organization $tenant

Write-log -Type Info -message "Connecting to Azure AD ..."
Connect-AzureAD -TenantId $Connection.TenantId -ApplicationId $Connection.ApplicationID -CertificateThumbprint $Connection.CertificateThumbprint 

#endregion

#region Main Script
########################################################

Write-log -Type Info -message "Getting users which should be able to use Remote PowerShell ..."

$UserstoIgnore = @()
foreach($ExceptionGroup in $ExceptionGroups){
    $UserstoIgnore += Get-AzureADGroupMember -ObjectId $ExceptionGroup
}

foreach($ExceptionRole in $ExceptionRoles){
    $role = Get-AzureADDirectoryRole | Where-Object { $ExceptionRole -eq $_.DisplayName }
    $UserstoIgnore += Get-AzureADDirectoryRoleMember -ObjectId $role.ObjectId | Where-Object { $_.ObjectType -ne "ServicePrincipal" }
}

Write-log -Type Info -message "Getting all Users with PowerShell enabled ..."
$Users = Get-User | Where-Object { $_.RemotePowerShellEnabled -eq $true }

#block users except their are member of designated group
ForEach($User in $Users){
    If($UserstoIgnore.UserPrincipalName -notcontains $User.UserPrincipalName){
        Write-log -Type Warn -message "Disabling Remote Powershell for $($User.UserPrincipalName) ..."
        Set-User -Identity $User.UserPrincipalName -RemotePowerShellEnabled $false
    }
}

Write-log -Type Info -message "Getting all Users with PowerShell disabled ..."
$Users = Get-User | Where-Object { $_.RemotePowerShellEnabled -eq $false }

# enable users which are member of designated group
ForEach($User in $Users){
    If($UserstoIgnore.UserPrincipalName -contains $User.UserPrincipalName){
        Write-log -Type Warn -message "Enable Remote Powershell for $($User.UserPrincipalName) ..."
        Set-User -Identity $User.UserPrincipalName -RemotePowerShellEnabled $true
    }
}

#endregion

#region Finishing
########################################################
Write-log -Type Info -message "Disconnect form Exchange Online"
Get-PSSession | Remove-PSSession

#Disconnect from Azure AD and Exchange Online
Disconnect-AzureAD -Confirm:$false
Disconnect-ExchangeOnline -Confirm:$false

Write-log -Type Info -message "End Script $scriptname "

#endregion