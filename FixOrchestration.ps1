$CMDBServer = 'CM1'
$DBName = 'ConfigMgr_CHQ'

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
,case when ogm.CurrentState=1 then 'Idle'
       when ogm.CurrentState=2 then 'Waiting'
       when ogm.CurrentState=3 then 'In Progress'
       when ogm.CurrentState=4 then 'Failed'
       when ogm.CurrentState=5 then 'Reboot Pending'
       else cast(ogm.CurrentState as nvarchar)
       end as 'CurrentStateName'
FROM [CM_MEM].[dbo].[vSMS_OrchestrationGroupMembers] OGM
join vSMS_OrchestrationGroup og
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
Where CurrentState =4
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
 
$FailedDevices = Invoke-Sqlcmd -Database $DBName -ServerInstance $CMDBServer -Query $query
 
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