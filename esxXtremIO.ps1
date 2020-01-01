# esxXtremIO.ps1 - Configure VMware ESXi for Dell-EMC XtremIO (v1) 
# Date          : 3rd August 2018
# Created By    : mrkips (Cybergavin) 
# Description   : This is a rudimentary interactive script (prompted for credentials) for ad hoc configuration
#                 of ESXi hosts for optimal performance with Dell-EMC XtremIO (v1) SAN.
#                 For Configuration details, refer  Chapter 3 in https://support.emc.com/docu56210_XtremIO-Host-Configuration-Guide.pdf
#                 For ESXi 6.5 U2 onwards, VMware Native MultiPathing (NMP) is set to Round-Robin with switching frequency (iops) of 1 by default.
# Environment   : ESXi 6.5 U2, XtremIO XIOS v4, PowerShell 6.1.0, PowerCLI 10
#########################################################################################
#
# Variables
#
$myname=[string] ($MyInvocation.MyCommand.Name)
#
# Usage
#
if ( $args.length -ne 2 )
{
@"

USAGE  : ./$myname <vCenter> <ESXi Cluster>
where,  <vCenter> = FQDN or IP Address of vCenter
        <ESXi Cluster> = Name of ESXi Cluster whose member Hosts are to be configured

EXAMPLE: ./$myname myvcenter LABCLUSTER 

"@
exit 100
}
#
# Setup PowerCLI and connect to the vCenter
#
Set-PowerCLIConfiguration -InvalidCertificateAction ignore -ProxyPolicy NoProxy -DefaultVIServerMode Single -ParticipateInCEIP $false -confirm:$false
Connect-VIServer -Server $args[0]
#
# Loop through all powered on and connected ESXi hosts in the ESXi cluster and configure settings
#
$vmhosts = Get-VMHost -Location $args[1] | Where { $_.PowerState -eq "PoweredOn" -and $_.ConnectionState -eq "Connected"}
foreach ($vmhost in $vmhosts) {
    Get-VMhostModule -VMHost $vmhost qlnativefc | Set-VMHostModule -Options "ql2xmaxqdepth=256"
    Get-AdvancedSetting -Entity $vmhost -Name Disk.DiskMaxIOSize | Set-AdvancedSetting -Value 4096
    Get-AdvancedSetting -Entity $vmhost -Name Disk.SchedQuantum | Set-AdvancedSetting -Value 64
    Get-AdvancedSetting -Entity $vmhost -Name DataMover.MaxHWTransferSize | Set-AdvancedSetting -Value 0256
    $esxcli = $vmhost | Get-EsxCli -V2
    $arguments = $esxcli.storage.core.device.set.CreateArgs()
    # Loop through all LUNs and set SchedNumReqOutstanding to be the same as LUN Maximum Queue Depth
    foreach ($i in $esxcli.storage.core.device.list.Invoke()){ 
        if ($i.Vendor -eq 'XtremIO' -and $i.DeviceType -eq 'Direct-Access') {
            $arguments.schednumreqoutstanding = $i.DeviceMaxQueueDepth
            $arguments.device = $i.Device
            $esxcli.storage.core.device.set.Invoke($arguments)
        }
    }
}