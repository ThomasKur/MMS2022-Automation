Param(
    $DayAfterDeadline = 2
)
Import-module SQLPS
Import-Module ConfigurationManager  

$SiteCode = Get-AutomationVariable -Name SiteCode #"CHQ" 
$MEMCMDB = Get-AutomationVariable -Name MEMCMDataBase #"ConfigMgr_CHQ" 
$MEMCMServer = Get-AutomationVariable -Name MEMCMServer # "CM1.corp.contoso.com" 

$initParams = @{}
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $MEMCMServer @initParams
}

$Query = "SELECT *
	  , CASE WHEN CollectionName like '%\[REQ]%' ESCAPE '\'
        AND DateDiff(Day,EnforcementDeadline,GetDate())>$DayAfterDeadline
        AND OverrideServiceWindows = 0 
       THEN 'SETNoMW' END 'Action'
  FROM [dbo].[v_CIAssignment]
  WHERE CollectionName like '%\[REQ]%' ESCAPE '\'"

$NeedsEnforcementDeployments = Invoke-Sqlcmd -ServerInstance $MEMCMServer  -Database $MEMCMDB -Query $query 

Foreach($NeedsEnforcement in $NeedsEnforcementDeployments){
    If ($NeedsEnforcement.StartTime -lt (Get-date)){
        Write-Output -InputObject "$($NeedsEnforcement.AssignmentName) Started $($NeedsEnforcement.StartTime) "
        If ([System.DBNull]::Value -NE $NeedsEnforcement.Action){
            Write-Output -InputObject "$($NeedsEnforcement.AssignmentName) Started $($NeedsEnforcement.EnforcementDeadline)"
            if (-not $NeedsEnforcement.OverrideServiceWindows){
                Write-Output -InputObject "$($NeedsEnforcement.AssignmentName) Setting Override"
                Push-Location "$($SiteCode):\" @initParams
                $Deployment = Get-CMDeployment -DeploymentId $NeedsEnforcement.Assignment_UniqueID
                Set-CMApplicationDeployment -InputObject $Deployment -OverrideServiceWindow $True
                Pop-Location
            }
        }Else{
            Write-Output -InputObject "$($NeedsEnforcement.AssignmentName) Ignoring ServiceWindows in $((New-TimeSpan $NeedsEnforcement.EnforcementDeadline (Get-Date)).TotalDays) days"
        }
    }
}