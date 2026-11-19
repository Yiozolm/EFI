# Creates the "MACOS" partition for macOS in the unallocated space on the internal KIOXIA SSD.
# Run from an *administrator* PowerShell:
#   powershell -ExecutionPolicy Bypass -File C:\Code\Hackintosh\redmibook-pro-15-2023-efi\Tools\make-macos-partition.ps1
# Only uses space that is already unallocated: no existing partition (Windows, EFI, recovery) is touched.
# In the macOS installer, erase ONLY this "MACOS" volume as APFS.

$ErrorActionPreference = 'Stop'

$disks = @(Get-Disk | Where-Object { $_.FriendlyName -match 'KIOXIA' -and $_.BusType -eq 'NVMe' })
if ($disks.Count -ne 1) { throw "Expected exactly one KIOXIA NVMe disk, found $($disks.Count). Aborting." }
$disk = $disks[0]
if ($disk.PartitionStyle -ne 'GPT') { throw "Disk $($disk.Number) is not GPT. Aborting." }

$free = $disk.LargestFreeExtent
if ($free -lt 150GB) { throw ("Largest unallocated area is only {0:N1} GB (expected about 200 GB). Aborting." -f ($free / 1GB)) }
if (Get-Volume -FileSystemLabel MACOS -ErrorAction SilentlyContinue) { throw 'A volume named MACOS already exists. Aborting.' }

Write-Host ("Disk {0}: {1}. Will create a {2:N1} GB exFAT partition 'MACOS' in the unallocated space." -f $disk.Number, $disk.FriendlyName, ($free / 1GB)) -ForegroundColor Yellow
Get-Partition -DiskNumber $disk.Number | Format-Table PartitionNumber, DriveLetter, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, Type -AutoSize
$answer = Read-Host 'Type YES to continue'
if ($answer -ne 'YES') { Write-Host 'Cancelled.'; exit 1 }

$before = @(Get-Partition -DiskNumber $disk.Number | ForEach-Object { "$($_.Offset):$($_.Size)" })
$p = New-Partition -DiskNumber $disk.Number -UseMaximumSize
Format-Volume -Partition $p -FileSystem exFAT -NewFileSystemLabel MACOS -Confirm:$false | Out-Null

# The existing partitions must be exactly as before.
$after = @(Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -ne $p.Offset } | ForEach-Object { "$($_.Offset):$($_.Size)" })
if (Compare-Object $before $after) { Write-Host 'WARNING: existing partitions changed!' -ForegroundColor Red; exit 2 }

Get-Partition -DiskNumber $disk.Number | Format-Table PartitionNumber, DriveLetter, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, Type -AutoSize
Write-Host 'MACOS partition created (no drive letter). In the macOS installer, erase only MACOS as APFS.' -ForegroundColor Green
