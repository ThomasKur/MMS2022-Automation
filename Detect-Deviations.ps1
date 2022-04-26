function Initialize-AssetCheck{
    param(
        [String[]]$SourceNames
    )
    $Script:SourceNames = $SourceNames
    $Script:Result = @()
}


function Invoke-AssetCheck{
    param(
        [String]$SourceName,
        [Object[]]$SourceObjects,
        [String]$KeyProperty
    )

    foreach($SourceObject in $SourceObjects){
        $ExistingObject = $Script:Result | Where-Object { $_.Key -eq ($SourceObject.$KeyProperty).ToLower()}
        if($ExistingObject){
            $ExistingObject.$SourceName = $SourceObject
        } else {
            $Object = New-Object PSObject            $Object | Add-Member -MemberType NoteProperty -Name Key -Value ($SourceObject.$KeyProperty).ToLower()            foreach($AllSourceName in $Script:SourceNames){                $Object | Add-Member -MemberType NoteProperty -Name $AllSourceName -Value $null            }            $Object.$SourceName = $SourceObject
            $Script:Result += $Object
        }
    }

    return $Script:Result

}

$cmdevices = Get-CMDevice
$addevices = Get-ADComputer -Filter *
Initialize-AssetCheck -SourceNames @("AD","MEMCM")
$r = Invoke-AssetCheck -SourceName "MEMCM" -SourceObjects $cmdevices -KeyProperty "Name"
$r = Invoke-AssetCheck -SourceName "AD" -SourceObjects $addevices -KeyProperty "Name"

$r | fl

# Good One 
$r | Where-Object {$_.AD -ne $null -and $_.MEMCM -ne $null}