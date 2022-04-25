<#
.Synopsis
Update-AllComputersGroups-T1
.DESCRIPTION
Adds all computers of a specific tier to the respective all computers group.
.EXAMPLE
Update-AllComputersGroups-T1
.NOTES
    v1.0, 14.9.2021, Thomas Kurth, initial version
#>
Import-Module ActiveDirectory
$dNC = (Get-ADRootDSE).defaultNamingContext
$Cred = Get-AutomationPSCredential -Name 'svc1azauto01'
$ADServer = Get-AutomationVariable -Name 'ADServer'
$Locations = @("GLOBAL","CHAG","USNY")
$MainOU = "KURCONTOSO"



$Tier1Computers = @()
$Tier1Computers += Get-ADComputer -Filter * -SearchBase "ou=Tier1,ou=Admin,$dNC" -Server $ADServer
foreach($l in $Locations){
    $Tier1Computers += Get-ADComputer -Filter * -SearchBase "ou=Tier 1 Services,ou=$l,ou=$MainOU,$dNC" -Server $ADServer
}
Write-Output "Found $($Tier1Computers.count) T1 computer accounts"
Add-ADGroupMember -Identity RG-GLOBAL-Tier1-AllComputers -Members $Tier1Computers -Credential $Cred -Server $ADServer

$ExistingMembers = Get-ADGroupMember -Identity RG-GLOBAL-Tier1-AllComputers -Server $ADServer | Where-Object { $Tier1Computers.SamAccountName -notcontains $_.SamAccountName } 

Write-Output "Found $($ExistingMembers.count) T1 computer accounts to remove from group"
foreach($ExistingMember in $ExistingMembers){
    Write-Warning "Remove $($ExistingMember.Name) from group"
    Remove-ADGroupMember -Identity RG-GLOBAL-Tier1-AllComputers $ExistingMember -Credential $Cred -Server $ADServer -Confirm:$false 
}