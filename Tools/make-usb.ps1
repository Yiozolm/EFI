# Builds the OpenCore + macOS Tahoe recovery USB on the SanDisk 3.2Gen1 (114.6 GB).
# Run from an *administrator* PowerShell:
#   powershell -ExecutionPolicy Bypass -File C:\Code\Hackintosh\redmibook-pro-15-2023-efi\Tools\make-usb.ps1
# ERASES the whole USB disk. Partition 1: FAT32 "OPENCORE" 16 GB (EFI + recovery), partition 2: exFAT "DATA" (rest).

$ErrorActionPreference = 'Stop'
$Repo     = 'C:\Code\Hackintosh\redmibook-pro-15-2023-efi'
$Recovery = Join-Path $env:TEMP 'recovery'   # folder with BaseSystem.dmg + BaseSystem.chunklist

# --- Preflight: inputs exist ---
foreach ($f in 'BaseSystem.dmg', 'BaseSystem.chunklist') {
    if (-not (Test-Path (Join-Path $Recovery $f))) { throw "Missing $Recovery\$f - recovery download not finished?" }
}
if (-not (Test-Path "$Repo\EFI\OC\config.plist")) { throw "EFI not found in $Repo" }

# --- Find exactly one USB SanDisk of ~114.6 GB; refuse anything else ---
$disks = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.FriendlyName -match 'SanDisk' -and [math]::Round($_.Size / 1GB, 1) -eq 114.6 })
if ($disks.Count -ne 1) { throw "Expected exactly one 114.6 GB USB SanDisk, found $($disks.Count). Aborting." }
$disk = $disks[0]
if ($disk.IsBoot -or $disk.IsSystem) { throw "Disk $($disk.Number) is a boot/system disk. Aborting." }

Write-Host "About to ERASE disk $($disk.Number): $($disk.FriendlyName), $([math]::Round($disk.Size/1GB,1)) GB, $($disk.BusType)" -ForegroundColor Yellow
$answer = Read-Host "Type YES to continue"
if ($answer -ne 'YES') { Write-Host 'Cancelled.'; exit 1 }

# --- Partition ---
Clear-Disk -Number $disk.Number -RemoveData -RemoveOEM -Confirm:$false
Initialize-Disk -Number $disk.Number -PartitionStyle GPT -ErrorAction SilentlyContinue
$p1 = New-Partition -DiskNumber $disk.Number -Size 16GB -AssignDriveLetter
Format-Volume -Partition $p1 -FileSystem FAT32 -NewFileSystemLabel OPENCORE -Confirm:$false | Out-Null
$p2 = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
Format-Volume -Partition $p2 -FileSystem exFAT -NewFileSystemLabel DATA -Confirm:$false | Out-Null
$oc   = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $p1.PartitionNumber).DriveLetter
$data = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $p2.PartitionNumber).DriveLetter
Write-Host "OPENCORE = ${oc}:   DATA = ${data}:"

# --- Copy EFI and recovery ---
robocopy "$Repo\EFI" "${oc}:\EFI" /E /NFL /NDL /NJH /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy EFI failed ($LASTEXITCODE)" }
New-Item -ItemType Directory -Path "${oc}:\com.apple.recovery.boot" | Out-Null
Copy-Item "$Recovery\BaseSystem.dmg", "$Recovery\BaseSystem.chunklist" "${oc}:\com.apple.recovery.boot\"

# --- Extras on DATA ---
Copy-Item "$Repo\Tools\HeliPort-1.5.0.dmg" "${data}:\"
robocopy "$Repo\EFI" "${data}:\EFI-backup" /E /NFL /NDL /NJH /NP | Out-Null

# --- Verify ---
$ok = $true
foreach ($f in "${oc}:\EFI\BOOT\BOOTx64.efi", "${oc}:\EFI\OC\OpenCore.efi", "${oc}:\EFI\OC\config.plist",
               "${oc}:\com.apple.recovery.boot\BaseSystem.dmg", "${oc}:\com.apple.recovery.boot\BaseSystem.chunklist",
               "${data}:\HeliPort-1.5.0.dmg") {
    if (Test-Path $f) { Write-Host "OK  $f" } else { Write-Host "MISSING  $f" -ForegroundColor Red; $ok = $false }
}
if ((Get-FileHash "$Recovery\BaseSystem.dmg").Hash -ne (Get-FileHash "${oc}:\com.apple.recovery.boot\BaseSystem.dmg").Hash) {
    Write-Host 'BaseSystem.dmg copy differs from the download!' -ForegroundColor Red; $ok = $false
}
if ($ok) { Write-Host 'USB installer is ready.' -ForegroundColor Green } else { exit 2 }
