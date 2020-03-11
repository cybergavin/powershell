# cybergavin - 09-MAR-2020
# Create a new group and add AD users as members, based on a filter

$myubase="OU=Satlab User Accounts,DC=SATLAB,DC=COM"
$mygbase="OU=Satlab Group Accounts,DC=SATLAB,DC=COM"
$mygroup = "MySatlab"
$mygroup_owner = "MARCOM"
$myusers = Get-ADUser -SearchBase $myubase -Properties employeeType -Filter "employeeType -eq 'REGULAR' -or employeeType -eq 'CONTRACTOR'"
New-ADGroup -Name $mygroup -Path $mygbase -Description "MySatlab Users" -GroupScope Global -GroupCategory Security -ManagedBy $mygroup_owner
Add-ADGroupMember -Identity $mygroup -Members $myusers