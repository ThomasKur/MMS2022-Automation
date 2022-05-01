Import-module SQLPS
Import-Module ConfigurationManager  

$MEMCMDB = Get-AutomationVariable -Name MEMCMDataBase #"ConfigMgr_CHQ" 
$MEMCMServer = Get-AutomationVariable -Name MEMCMServer # "CM1.corp.contoso.com" 

$Query = "
with CTE As (SELECT
    og.Name 'GroupName'
    ,OGM.[Name]
    ,OGM.[SiteCode]
    ,[IsActive]
    ,OGM.[MOGID]
    ,[ResourceID]
    ,OGM.[MOG_UniqueID]
    ,OGM.SequenceNumber
    ,[CurrentState]
    ,[StateCode]
    ,[LockAcquiredTime]
    ,[LastStateReportedTime]
    ,s.ServerName
    ,CASE WHEN ogm.CurrentState=1 THEN 'Idle'
        WHEN  ogm.CurrentState=2 THEN 'Waiting'
        WHEN ogm.CurrentState=3 THEN 'In Progress'
        WHEN ogm.CurrentState=4 THEN 'Failed'
        WHEN ogm.CurrentState=5 THEN 'Reboot Pending'
        ELSE cast(ogm.CurrentState as nvarchar)
        END as 'CurrentStateName'
    FROM [dbo].[vSMS_OrchestrationGroupMembers] OGM
        INNER JOIN vSMS_OrchestrationGroup og
            on og.MOG_UniqueID=ogm.MOG_UniqueID
        INNER JOIN [dbo].[v_Site] s
            on S.SiteCode = OGM.SiteCode
)
 
SELECT 
    GroupName
    ,[SiteCode]
    ,[IsActive]
    ,[MOGID]
    ,[MOG_UniqueID]
    ,[CurrentState]
    ,[StateCode]
    ,[LockAcquiredTime]
    ,ServerName
    ,STRING_AGG((cast([ResourceID]as nvarchar(10))+'-'+[name]),',')WITHIN GROUP ( ORDER BY SequenceNumber) 'Resourceids'
FROM CTE
WHERE CurrentState =4
GROUP BY GroupName
    ,[SiteCode]
    ,[IsActive]
    ,[MOGID]
    ,[MOG_UniqueID]
    ,[CurrentState]
    ,[StateCode]
    ,[LockAcquiredTime]
    ,ServerName

"
 
$FailedDevices = Invoke-Sqlcmd -Database $MEMCMDB -ServerInstance $MEMCMServer -Query $query
 
foreach($FailedDev in $FailedDevices){
    New-PSDrive -Name $FailedDev.SiteCode -PSProvider CMSite -Root $FailedDev.ServerName
    Push-Location "$($FailedDev.SiteCode):\"
    $OrchstrationClass = Get-WmiObject -ComputerName $FailedDev.ServerName -Namespace "Root\SMS\SITE_$($FailedDev.SiteCode)" -ClassName SMS_MachineOrchestrationGroup -list
    foreach($System in $FailedDev.Resourceids.split(',')){
        $ResourceID = $system.split('-')[0]
        $Name = $system.split('-')[1]
        Write-Output -InputObject "Fixing $Name"
        $OrchstrationClass.ResetMOGMember($ResourceID);
    }
    Get-CMOrchestrationGroup -Name $Faileddev.GroupName | Invoke-CMOrchestrationGroup -IgnoreServiceWindow $true
    Pop-Location
}