$MinDeviceCount = 3
$MaxCOllectionToMake = 2
$Folder = 'Models'
$NamingStandard = 'Models_<Manufacturer>_<Model>'
$SiteCode = "CHQ" # Site code 
$ProviderMachineName = "CM1.corp.contoso.com" # SMS Provider machine name
$LimitingCollection = 'SMS00001'

Import-module SQLPS
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

$initParams = @{}
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}


$Query = "
With ModelCTE As (
       Select Model0, Manufacturer0, Count(*) 'Count', 'V_GS_Computer_System' 'View'
       From V_GS_Computer_System
       Where Manufacturer0 in ('HP','DELL Inc.','VMware, Inc.','Microsoft Corporation')
       Group By Model0, Manufacturer0
       /*
       Union All

       Select Version0, Vendor0, Count(*) 'Count', 'V_GS_Computer_System_Product' 'View'
             From V_GS_Computer_System_Product
             Where Vendor0 in ('LENOVO')
             Group By Version0, Vendor0
             */
)
Select *
From ModelCTE
Where [Count] > $MinDeviceCount
order by [Count] Desc, Model0, Manufacturer0"
$Models = Invoke-Sqlcmd -ServerInstance CM1 -Database ConfigMgr_CHQ -Query $query

Push-Location "$($SiteCode):\"
$Schedule = New-CMSchedule -DayOfWeek Saturday 
$FolderObject = Get-CMFolder -Name $Folder
if ($Null -eq $folderObject){
    New-CMFolder -Name $folder 
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

    Add-CMCollectionMembershipRule -RuleClassName
}
Pop-Location