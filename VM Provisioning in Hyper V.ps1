# Provision-MultiVM.ps1
# Author: Shubham Singh
# Date: 2024-06-28
# Description: Provision VM across Hyper-V nodes, tag, snapshot, and domain join

#===================== USER CONFIGURATION =====================#
$VMName           = "CustomVM01"
$VHDSizeGB        = 60
$MemoryStartup    = 4GB
$CPUCount         = 2
$SwitchName       = "Default Switch"
$ISOPath          = "D:\ISOs\WinServer2022.iso"
$Generation       = 2
$EnableAutoStart  = $true
$DomainName       = "corp.local"
$DomainUser       = "corp\\adminuser"
$DomainPass       = Read-Host "Enter domain password" -AsSecureString
$CustomNotes      = "Created by script, June 2025, Owner: Shubham"
$WaitBeforeSnap   = 300   # Wait time in seconds before snapshot (simulate install time)
$HyperVHosts      = @("HV-Node1", "HV-Node2")  # Remote Hyper-V nodes
#==============================================================#

#====================== SCRIPT LOGIC ==========================#

foreach ($host in $HyperVHosts) {
    Write-Host "`n==== Provisioning on $host ====" -ForegroundColor Cyan

    Invoke-Command -ComputerName $host -ScriptBlock {
        param(
            $VMName, $VHDSizeGB, $MemoryStartup, $CPUCount, $SwitchName, 
            $ISOPath, $Generation, $EnableAutoStart, $DomainName, 
            $DomainUser, $SecureDomainPass, $CustomNotes, $WaitBeforeSnap
        )

        $VMPath = "D:\VMs\$VMName"
        $VHDPath = "$VMPath\$VMName.vhdx"
        $LogFile = "$VMPath\ProvisionLog.txt"

        function Write-Log {
            param($Message)
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "$timestamp - $Message" | Tee-Object -FilePath $LogFile -Append
        }

        try {
            Write-Log "=== Starting VM provisioning on $env:COMPUTERNAME ==="
            if (Test-Path $VMPath) {
                throw "VM path already exists: $VMPath"
            }

            # Create VM directory
            New-Item -ItemType Directory -Path $VMPath -Force | Out-Null

            # Create virtual disk
            Write-Log "Creating virtual disk: $VHDPath"
            New-VHD -Path $VHDPath -SizeBytes (${VHDSizeGB}GB) -Dynamic | Out-Null

            # Create VM
            Write-Log "Creating VM: $VMName"
            New-VM -Name $VMName -MemoryStartupBytes $MemoryStartup -Generation $Generation `
                   -VHDPath $VHDPath -SwitchName $SwitchName -Path $VMPath | Out-Null

            # Configure CPU
            Write-Log "Configuring CPU: $CPUCount vCPU"
            Set-VMProcessor -VMName $VMName -Count $CPUCount

            # Attach ISO
            Write-Log "Attaching ISO: $ISOPath"
            Add-VMDvdDrive -VMName $VMName -Path $ISOPath

            # Set AutoStart
            if ($EnableAutoStart) {
                Set-VM -Name $VMName -AutomaticStartAction StartIfRunning
                Write-Log "Auto-start enabled."
            }

            # Add Notes / Metadata
            Set-VM -Name $VMName -Notes $CustomNotes
            Write-Log "Added VM notes: $CustomNotes"

            # Start VM
            Write-Log "Starting VM..."
            Start-VM -Name $VMName
            Write-Log "VM started."

            # Wait before snapshot
            Write-Log "Waiting $WaitBeforeSnap seconds for installation..."
            Start-Sleep -Seconds $WaitBeforeSnap

            # Take snapshot
            Write-Log "Taking snapshot after installation"
            Checkpoint-VM -Name $VMName -SnapshotName "Post-Install-Snapshot"

            # Join domain using PowerShell Direct
            Write-Log "Initiating domain join..."
            $Cred = New-Object System.Management.Automation.PSCredential($DomainUser, $SecureDomainPass)
            Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock {
                Add-Computer -DomainName $using:DomainName -Credential $using:Cred -Force -Restart
            }

            Write-Log "Domain join command issued."
            Write-Log "=== VM provisioning completed successfully ==="

        } catch {
            Write-Log "ERROR: $_"
            Write-Error "Failed on host $env:COMPUTERNAME: $_"
        }

    } -ArgumentList $VMName, $VHDSizeGB, $MemoryStartup, $CPUCount, $SwitchName, `
        $ISOPath, $Generation, $EnableAutoStart, $DomainName, $DomainUser, `
        $DomainPass, $CustomNotes, $WaitBeforeSnap
}
