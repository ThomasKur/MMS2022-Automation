Param(
    $CollectionNamingStandard = 'Enterprise_Rollout_<Ring>',
    $UserADGroupNamingStandard = 'Enterprise Rollout User <Ring>'
)
Import-module SQLPS
Import-Module ConfigurationManager  


$Rings = [ordered]@{Ring1=.1;Ring2=.2;Ring3=.3;Ring4=.4}

$NamingStandard = Get-AutomationVariable -Name ModelsCollectionNamingStandard #'Models_<Manufacturer>_<Model>'
$SiteCode = Get-AutomationVariable -Name SiteCode #"CHQ" 
$MEMCMDB = Get-AutomationVariable -Name MEMCMDataBase #"ConfigMgr_CHQ" 
$MEMCMServer = Get-AutomationVariable -Name MEMCMServer # "CM1.corp.contoso.com" 
$RootCollection = Get-AutomationVariable -Name DefaultLimitingCollection #'SMS00001'
$DesktopCollection = Get-AutomationVariable -Name DesktopCollection #'CHQ0002B'
$ADGroupPath = Get-AutomationVariable -Name ADGroupPath #'OU=GROUPS,OU=CORP,DC=corp,DC=contoso,DC=com'
$Credential = Get-AutomationPSCredential -name LabAdmin


$initParams = @{}
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $MEMCMServer @initParams
}

$Query = "WITH WeightedCTE as (
	SELECT
		u.Resourceid 'UserResourceID',
		u.User_Name0,
		u.Distinguished_Name0,
		u.Company,
		M.ResourceID 'MachineID',
		M.Netbios_Name0,

		Row_Number() Over (Partition by u.Company order by u.SID0) 'BusinessUnitRN',
		COUNT(*) Over (Partition by u.Company) 'BusinessUnitCount',

		Row_Number() Over (Partition by cs.Model0 order by m.SMS_Unique_Identifier0) 'ModelRN',
		COUNT(*) Over (Partition by cs.Model0) 'ModelCount'
	FROM v_R_User u
	INNER JOIN v_UsersPrimaryMachines pu
		on pu.UserResourceID = u.ResourceID
	INNER JOIN v_R_System M
		on M.ResourceID = pu.MachineID
	INNER JOIN v_GS_COMPUTER_SYSTEM CS
		on CS.ResourceID = m.ResourceID
)

SELECT WeightedCTE.*
FROM WeightedCTE
INNER JOIN v_FullCollectionMembership_Valid FCM
ON FCM.ResourceID = WeightedCTE.MachineID and FCM.CollectionID = '$DesktopCollection'
Order by (BusinessUnitRN*100/BusinessUnitCount + ModelRN*100/ModelCount) desc
"
$Candidates = Invoke-Sqlcmd -ServerInstance $MEMCMServer  -Database $MEMCMDB -Query $query

#Identify candidates and who is already in a ring
$CandidateTotal = $Candidates.Count
$Index = 0
[array]$ExistingADGroups = Get-ADGroup -LDAPFilter "(Name=$($UserADGroupNamingStandard.replace('<Ring>','*')))" -Properties member -Credential $Credential
$RingCandidates = $Candidates.Where({$PSItem.Distinguished_Name0 -notin $ExistingADGroups.Member})
"Total Candidates: $candidateTotal"
$ExistingADGroups.foreach({"$($Psitem.SamAccountName) - $($Psitem.member.count)"})
"Total Remaining: $($RingCandidates.Count)"


#Setup Rings
Foreach($Ring in $Rings.Keys){
    Write-output -InputObject "$ring"
    #Setup AD Group
    $ADGroupName = $UserADGroupNamingStandard.replace('<Ring>',$Ring)
    $ADGroup = $ExistingADGroups.Where({$PSItem.SamAccountName -eq $ADGroupName})[0]
    if ($Null -eq $ADGroup)
    {
        Write-Output -InputObject "Making AD Group for $Ring - $ADGroupName"
        $ADGroup = New-ADGroup -Name $ADGroupName -Path $ADGroupPath -Description "Enterprise Rollout Group for $Ring" -PassThru -GroupScope Global -GroupCategory Distribution  -Credential $Credential
    }

    #Populate AD Group
    $RingPercentage = $rings[$ring]
    $TargetPopulation = [Math]::Floor(($RingPercentage * $CandidateTotal)  - $ADGroup.Member.count)
    if ($TargetPopulation -gt 0){
        $Users = $RingCandidates[$index..($TargetPopulation+$index)]
        if ($Users.Count -gt 0){
            Write-output -InputObject "Adding $($TargetPopulation + 1) to $adgroupname"
            Add-ADGroupMember -Members $Users.Distinguished_Name0 -Identity $ADGroupName -Credential $Credential
        }
        $Index = $Index + $TargetPopulation +1
    }
    $ADGroup = Get-ADGroup $ADGroupName -Properties member -Credential $Credential
    $users = $Candidates.where({$PSItem.Distinguished_Name0 -in $ADGroup.member})
    Write-Output -InputObject "$ADGroupName now has $($adgroup.member.count) members"

    #Update Collection
    Push-Location -Path "$($SiteCode):\"
    $CollectionName = $CollectionNamingStandard.Replace('<Ring>',$Ring)
    $Collection = Get-CMCollection -Name $CollectionName
    if ($Null -eq $Collection){
        Write-Output -InputObject "Making Collection $CollectionName"
        $Collection = New-CMCollection -CollectionType Device -LimitingCollectionId $RootCollection -Name $CollectionName -Comment "Made by Azure Automation!"
    }

    #Setting CM Membership
    Add-CMDeviceCollectionDirectMembershipRule -CollectionId $Collection.CollectionID -ResourceId $users.MachineID -WarningAction Ignore
}



#ResetAD: $ExistingADGroups.SamAccountName | Remove-ADGroup
#Reset Collections:Get-CMDeviceCollection -name $CollectionNamingStandard.Replace("<Ring>",'*')| Remove-CMDeviceCollection 