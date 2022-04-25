<#
.DESCRIPTION
This script will remove duplicated devices based on the serial from Intune.
Remove duplicate intune devices based on device serial numbers
        Caution with duplicates caused by some OEM's
        Function adapted from https://www.wpninjas.ch/2019/09/cleanup-duplicated-devices-in-intune/


The Service Principal(RunAs) of the Azure Automation Workspace requires:
 - MSGraph
   - DeviceManagementManagedDevices.ReadWrite.All

.EXAMPLE


.NOTES
Author: Thomas Kurth/baseVISION
Date:   20.11.2021

History
    001: First Version

ExitCodes:
    99001: Could not Write to LogFile
    99002: Could not Write to Windows Log
    99003: Could not Set ExitMessageRegistry
#>

[CmdletBinding()]
Param()

## Manual Variable Definition
########################################################

$DebugPreference = "Continue"
$ScriptVersion = "001"
$ScriptName = "Invoke-IntuneCleanup"

$LogFilePathFolder = "C:\Windows\Logs"
$FallbackScriptPath = "C:\Windows" # This is only used if the filename could not be resolved(IE running in ISE)

# Log Configuration
$DefaultLogOutputMode = "Console" # "Console-LogFile","Console-WindowsEvent","LogFile-WindowsEvent","Console","LogFile","WindowsEvent","All"
$DefaultLogWindowsEventSource = $ScriptName
$DefaultLogWindowsEventLog = "CustomPS"

# Azure Automation
$RunningInAA = $true

$excludedSerialNumbers = @("Defaultstring", "ToBeFilledByO.E.M.")
 
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

Function Invoke-Graph(){
    <#
    .SYNOPSIS
    This function Requests information from Microsoft Graph
    .DESCRIPTION
    This function Requests information from Microsoft Graph and returns the value as Object[]
    .EXAMPLE
    Invoke-DocGraph -url ""
    Returns "Type"
    .NOTES
    NAME: Thomas Kurth 3.3.2021
    #>
    [OutputType('System.Object[]')]
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName = "FullPath")]
        $FullUrl,

        [Parameter(Mandatory=$true,ParameterSetName = "Path")]
        [string]$Path,

        [Parameter(Mandatory=$false,ParameterSetName = "Path")]
        [string]$BaseUrl = "https://graph.microsoft.com/",

        [Parameter(Mandatory=$false,ParameterSetName = "Path")]
        [switch]$Beta,

        [Parameter(Mandatory=$false,ParameterSetName = "Path")]
        [string]$AcceptLanguage,

        [Parameter(Mandatory=$false,ParameterSetName = "Path")]
        [ValidateSet('GET','DELETE')]
        [string]$Method = "GET"


    )
    if($PSCmdlet.ParameterSetName -eq "Path"){
        if($Beta){
            $version = "beta"
        } else {
            $version = "v1.0"
        }
        $FullUrl = "$BaseUrl$version$Path"
    }

    try{
        $header = @{Authorization = "Bearer $($script:token.AccessToken)"}
        if($AcceptLanguage){
            $header.Add("Accept-Language",$AcceptLanguage)
        }
        $value = Invoke-RestMethod -Headers $header -Uri  $FullUrl -Method $Method -ErrorAction Stop
    } catch {
        
        if($_.Exception.Response.StatusCode -eq "Forbidden"){
            throw "Used application does not have sufficiant permission to access: $FullUrl"
        } else {
            Write-Error $_
        }
    }

    return $value
}

#endregion

#region Dynamic Variables and Parameters
########################################################

# Try get actual ScriptName
try {
    $CurrentFileNameTemp = $MyInvocation.MyCommand.Name
    If ($CurrentFileNameTemp -eq $null -or $CurrentFileNameTemp -eq "") {
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

if (!(Test-Path $LogFilePathFolder)) {
    New-Folder $LogFilePathFolder
}

Write-Log "Start Script $Scriptname"

if($RunningInAA){ 
    $connection = Get-AutomationConnection -Name AzureRunAsConnection
    
    # Azure AD
    $AADAuthBody = @{
        TenantID                = $Connection.TenantId 
        ClientID           = $Connection.ApplicationID
        ClientCertificate   = (get-item Cert:\CurrentUser\my\$($Connection.CertificateThumbprint))
    }

} else {
    
    # Azure AD  - intune default app registration will force interactive
    $AADAuthBody = @{
        ClientId    = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547"
        RedirectUri = "urn:ietf:wg:oauth:2.0:oob"
    }
}

try {
    Write-log -Type Info -message "Connecting to MS Graph ..."
    
    if($null -eq $GraphAuthHeader){
        #get Azure Token
        $accesstokenazure = Get-MsalToken @AADAuthBody
        #Azure Header
        $script:token = $accesstokenazure
    }
    Write-Log -Message "Token successfully created" -Type Info
}
catch {
    Write-Log -Message "Get Token Failed" -Type Error -Exception $_.Exception
    throw "Get Token failed, stopping script."
}

#endregion

#region Main Script
########################################################

$devices = (Invoke-Graph -Path "/deviceManagement/managedDevices").Value
Write-Log -Message "Found $($devices.Count) devices."
$deviceGroups = $devices | Where-Object { -not [String]::IsNullOrWhiteSpace($_.serialNumber) -and $_.serialNumber -notin $excludedSerialNumbers } | Group-Object -Property serialNumber
$duplicatedDevices = $deviceGroups | Where-Object { $_.Count -gt 1 }
Write-Log -Message "Found $($duplicatedDevices.Count) serialNumbers with duplicated entries"
foreach ($duplicatedDevice in $duplicatedDevices) {
    # Find device which is the newest.
    $newestDevice = $duplicatedDevice.Group | Sort-Object -Property lastSyncDateTime -Descending | Select-Object -First 1
    Write-Log -Message "Serial $($duplicatedDevice.Name)"
    Write-Log -Message "# Keep $($newestDevice.deviceName) $($newestDevice.lastSyncDateTime)"
    foreach ($oldDevice in ($duplicatedDevice.Group | Sort-Object -Property lastSyncDateTime -Descending | Select-Object -Skip 1)) {
        Write-Log -Message "# Remove $($oldDevice.deviceName) $($oldDevice.lastSyncDateTime)"
        if ($PSCmdlet.ShouldProcess($oldDevice.id, "Deleting device")) {
            Invoke-Graph -Path "/deviceManagement/managedDevices/$($oldDevice.id)" -Method "DELETE" 
        }
    }
}


#endregion

#region Finishing
########################################################

Write-log -message "End Script $scriptname" -Type Info

#endregion