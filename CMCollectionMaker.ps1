Param
(
    $MinDeviceCount = 2,
    $MaxCOllectionToMake = 2
)
$Folder = Get-AutomationVariable -Name ModelsFolder # 'Models'
$NamingStandard = Get-AutomationVariable -Name ModelsCollectionNamingStandard #'Models_<Manufacturer>_<Model>'
$SiteCode = Get-AutomationVariable -Name SiteCode #"CHQ" 
$MEMCMDB = Get-AutomationVariable -Name MEMCMDataBase #"ConfigMgr_CHQ" 
$MEMCMServer = Get-AutomationVariable -Name MEMCMServer # "CM1.corp.contoso.com" 
$LimitingCollection = Get-AutomationVariable -Name DefaultLimitingCollection #'SMS00001'

Import-module SQLPS
Import-Module ConfigurationManager  

$initParams = @{}
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $MEMCMServer @initParams
}


$Query = "
With ModelCTE As (
       Select Model0, Manufacturer0, Count(*) 'Count', 'SMS_G_System_COMPUTER_SYSTEM' 'Class', 'Model' 'Property'
       From V_GS_Computer_System
       Where Manufacturer0 in ('HP','DELL Inc.','VMware, Inc.','Microsoft Corporation')
       Group By Model0, Manufacturer0
       /*
       Union All

       Select Version0, Vendor0, Count(*) 'Count', 'SMS_G_System_COMPUTER_SYSTEM_PRODUCT' 'Class', 'Version' 'Property'
             From V_GS_Computer_System_Product
             Where Vendor0 in ('LENOVO')
             Group By Version0, Vendor0
             */
)
Select *
From ModelCTE
Where [Count] > $MinDeviceCount
order by [Count] Desc, Model0, Manufacturer0"
$Models = Invoke-Sqlcmd -ServerInstance $MEMCMServer -Database $MEMCMDB -Query $query



Push-Location "$($SiteCode):\"
$Schedule = New-CMSchedule -DayOfWeek Saturday -Start (get-date)
$FolderObject = Get-CMFolder -Name $Folder
if ($Null -eq $folderObject){
    Write-Output -InputObject "Making Folder $folder"
    $FolderObject = New-CMFolder -Name $Folder -ParentFolderPath "$($SiteCode):\DeviceCollection" -ErrorAction Ignore
}

$CollecitonMade = 0
Foreach($Model in $models){
    if ($CollecitonMade -gt $MaxCOllectionToMake){
    Write-Output -InputObject "Exiting because we hit the max collections to make."
        Break
    }
    if ([string]::IsNullOrWhiteSpace($model.Model0)){
        Write-Warning -Message "Empty Model name $model"
        Continue
    }
    if ([string]::IsNullOrWhiteSpace($model.Manufacturer0)){
        Write-Warning -Message "Empty Manufacturer name $model"
        Continue
    }

    $COllectionName = $NamingStandard.Replace('<Manufacturer>',$model.Manufacturer0.replace(' ',''))
    $COllectionName = $COllectionName.Replace('<Model>',$model.Model0.replace(' ',''))
    $collection = Get-CMCollection -Name $COllectionName
    if ($collection){
        Continue
    }

    Write-Output -InputObject "Making Collection $CollectionName"
    $Collection = New-CMCollection -Name $COllectionName -LimitingCollectionId $LimitingCollection -RefreshSchedule $Schedule -CollectionType Device -Comment "Made by Azure Automation!"
    Move-CMObject -FolderPath "$($SiteCode):\DeviceCollection\$Folder" -InputObject $collection
    $COlQuery = "select *  from  SMS_R_System inner join {0} on {0}.ResourceId = SMS_R_System.ResourceId where {0}.{1} = '{2}'" -f   $model.Class, $model.Property, $model.model0
    Add-CMDeviceCollectionQueryMembershipRule -CollectionId $COllection.CollectionID -QueryExpression $COlQuery -RuleName $COllectionName -ValidateQueryHasResult

    $CollecitonMade++
    if ($CollecitonMade -gt $MaxCOllectionToMake){
        Write-Warning -Message 'Hit Max collections made in one run.'
        Break
    }
}
Pop-Location