# viDB.ps1 - Virtual Infrastructure Dashboard for VMware
# Date		: 2nd December 2017
# Created By	: mrkips (Cybergavin)
# Description	: A rudimentary script that collects data from vCenters and streams the date to a graphite server for display
#		  on Grafana dashboards. 
# 	          Tested on Windows Server 2019 with Powershell 5.
# Pre-Requisites: (1) Set variable values <vidb-dir>,<carbon-IP>,<carbon-PORT>,<vcentern>. You may add more vCenter IPs or resolvable FQDNs.
# 		  (2) Use a common credential for all vCenters and create a PS credential file $vidbdir\vcenter-creds.xml
#                 (3) Remove the "18000" adjustment in $epochTime if the remote graphite server is running on a Windows host.
#############################################################################################################################################
Start-Transcript -path viDB.txt
#
# Variables
#
$vidbdir = "<vidb-dir>" 
$vidbfile = "$vidbdir\viDB_$(Get-Date -Format `"yyyyMMddHmm`").txt"
$epochTime = [int](Get-Date -UFormat "%s") + 18000 # Adding 18000 to equate epoch time calculation between Windows and Linux (graphite on Linux)
$carbonServer = "<carbon-IP>"
$carbonServerPort = "<carbon-PORT>"
#
# Create Output Directory
#
if (!(Test-Path -Path $vidbdir))
	{
	New-Item -Path $vidbdir  -ItemType directory -Force
	}
#
# Initialize PowerCLI and vCenter Connections - Connect to all vCenters
#
Add-PSSnapin VMware.VimAutomation.Core
Set-PowerCLIConfiguration -InvalidCertificateAction ignore -confirm:$false
Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -confirm:$false
$Hosts = @("<vcenter1>","<vcenter2>","<vcenter3>")
$Hosts | %{
$creds = Get-VICredentialStoreItem -File "$vidbdir\vcenter-creds.xml" -Host $_
Connect-VIServer -Server $creds.host -User $creds.User -Password $creds.Password
}
$creds = $null
#
# ESXi Host Metrics
#
$myvhost = Get-VMHost | where-object {$_.PowerState -eq 'PoweredOn'} | Sort Name | Get-View |
Select Name,
@{N="cpu";E={$_.Hardware.CpuInfo.NumCpuPackages}},
@{N="cores";E={$_.Hardware.CpuInfo.NumCpuCores}},
@{N="memory";E={[math]::round($_.Hardware.MemorySize/1GB,0)}}
("vi.capacity.vhost.count " +($myvhost |Measure-Object "Name").Count + " " + $epochTime) | Out-File $vidbfile
("vi.capacity.vhost.cpu.count " +($myvhost | Measure-object "cpu" -Sum).Sum + " " + $epochTime) | Out-File -Append $vidbfile
("vi.capacity.vhost.cpu.core.count " +($myvhost | Measure-object "cores" -Sum).Sum + " " + $epochTime) | Out-File -Append $vidbfile
("vi.capacity.vhost.memory.total " +([math]::round(($myvhost | Measure-object "memory" -Sum).Sum/1024,2)) + " " + $epochTime) | Out-File -Append $vidbfile
#
# VM Metrics
#
$myvm = Get-VM
$myvm_on = $myvm | where-object {$_.PowerState -eq "PoweredOn"}
$myvm_os = foreach ($vm in $myvm_on) {(Get-View $vm).summary.Config.GuestFullName}
("vi.provisioned.vm.count " + ($myvm | Measure-Object).Count + " " + $epochTime) | Out-File -Append $vidbfile
("vi.provisioned.vm.vpu.total " + ($myvm_on | Measure-Object -Sum NumCPU).Sum  + " " + $epochTime) | Out-File -Append $vidbfile
("vi.provisioned.vm.memory.total " + ([math]::round(($myvm_on | Measure-Object -Sum MemoryGB).Sum/1024,2)) + " " + $epochTime) | Out-File -Append $vidbfile
("vi.provisioned.storage.total " + ([math]::round(($myvm | Get-HardDisk | measure-Object -Sum CapacityGB).Sum/1024,0)) + " " + $epochTime) | Out-File -Append $vidbfile
("vi.provisioned.vm.guestos.linux.count " + ($myvm_os -match 'Linux').count + " " + $epochTime) | Out-File -Append $vidbfile
("vi.provisioned.vm.guestos.windows.count " + ($myvm_os -match 'Windows').count + " " + $epochTime) | Out-File -Append $vidbfile
#
# Storage Metrics
#
$myds = [math]::round(((Get-Datastore | Measure-Object -Sum CapacityGB).Sum)/1024,0)
("vi.capacity.storage.total " + $myds + " " + $epochTime) | Out-File -Append $vidbfile
#
# Disconnect from vCenters
#
if ($Global:DefaultVIServers)
	{
		Disconnect-VIServer -Server * -Force -Confirm:$false
	}
#
#Stream results to the Carbon server
#
$socket = New-Object System.Net.Sockets.TCPClient 
$socket.connect($carbonServer, $carbonServerPort) 
$stream = $socket.GetStream() 
$writer = New-Object System.IO.StreamWriter($stream)
foreach($line in Get-Content $vidbfile) {
		$writer.WriteLine($line)
		}
$writer.Flush()
$writer.Close() 
$stream.Close()
$socket.Close()
Stop-Transcript
################################################# THE END ##################################################
