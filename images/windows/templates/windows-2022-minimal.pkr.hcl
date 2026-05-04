# windows-2022-minimal-dotnet.pkr.hcl
# Minimal .NET Framework build environment
# Uses official Microsoft scripts from runner-images repo

# ============================================================================
# REQUIRED PLUGINS
# ============================================================================

packer {
  required_version = ">= 1.7.0"
  required_plugins {
    hyperv = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/hyperv"
    }
  }
}

# ============================================================================
# VARIABLES
# ============================================================================

variable "iso_url" {
  type    = string
  # MODIFICA QUESTO PATH con la tua ISO location
  default = "file:///D:/virtual machine/SERVER_EVAL_x64FRE_en-us.iso"
}

variable "iso_checksum" {
  type    = string
  default = "none"
}

variable "vm_name" {
  type    = string
  default = "BuildAgent-2022"
}

variable "output_directory" {
  type    = string
  default = "output-hyperv"
}

variable "winrm_username" {
  type    = string
  default = "installer"
}

variable "winrm_password" {
  type      = string
  default   = "P@ssw0rd123!"
  sensitive = true
}

variable "image_folder" {
  type    = string
  default = "C:\\image"
}

# ============================================================================
# SOURCE
# ============================================================================

source "hyperv-iso" "vm" {
  # ISO Configuration
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum
  
  # VM Configuration
  vm_name              = var.vm_name
  generation           = 2
  switch_name          = "Default Switch"
  enable_secure_boot   = false
  enable_dynamic_memory = true
  memory               = 8192
  cpus                 = 4
  disk_size            = 81920  # 80GB
  disk_block_size      = 1
  
  # Output
  output_directory = var.output_directory
  
  # Boot
  boot_wait    = "3s"
  boot_command = ["<enter>"]
  
  # Unattended installation files (path relativi a images/windows/templates/)
  cd_files = [
    "${path.root}/../answer_files/Autounattend.xml",
    "${path.root}/../scripts/provisioners/"
  ]
  
  # WinRM Configuration
  communicator   = "winrm"
  winrm_username = var.winrm_username
  winrm_password = var.winrm_password
  winrm_timeout  = "12h"
  winrm_use_ssl  = false
  
  # Shutdown
  shutdown_command = "C:\\Windows\\System32\\Sysprep\\Sysprep.exe /generalize /oobe /shutdown /quiet"
  shutdown_timeout = "1h"
}

# ============================================================================
# BUILD
# ============================================================================

build {
  sources = ["source.hyperv-iso.vm"]

  # === PHASE 1: Initial Setup ===
  provisioner "powershell" {
    inline = [
      "Write-Host 'Creating image folder...'",
      "New-Item -Path '${var.image_folder}' -ItemType Directory -Force | Out-Null"
    ]
  }

  # === PHASE 2: Configure Windows ===
  provisioner "powershell" {
    environment_vars = ["IMAGE_VERSION=minimal-dotnet"]
    scripts          = ["${path.root}/../scripts/build/Configure-WindowsDefender.ps1"]
  }

  provisioner "powershell" {
    scripts = ["${path.root}/../scripts/build/Configure-DynamicPort.ps1"]
  }

  provisioner "powershell" {
    scripts = ["${path.root}/../scripts/build/Configure-PowerShell.ps1"]
  }

  # === PHASE 3: Install PowerShell 7 ===
  provisioner "powershell" {
    scripts = ["${path.root}/../scripts/build/Install-PowerShellCore.ps1"]
  }

  # === PHASE 4: Install Chocolatey ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-Chocolatey.ps1"]
  }

  # === PHASE 5: Install Git ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-Git.ps1"]
  }

  # === PHASE 6: Install .NET Framework ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = [
      "${path.root}/../scripts/build/Install-NET48.ps1"
    ]
  }

  # === PHASE 7: Install .NET SDK ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-DotnetSDK.ps1"]
  }

  # === PHASE 8: Install Visual Studio Build Tools ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    environment_vars  = ["TOOLSET_VERSION=2022"]
    scripts           = ["${path.root}/../scripts/build/Install-VisualStudio.ps1"]
  }

  # === PHASE 9: Install NuGet ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-Nuget.ps1"]
  }

  # === PHASE 10: Create Agent Directory Structure ===
  provisioner "powershell" {
    inline = [
      "Write-Host 'Creating agent directory structure...'",
      "New-Item -Path 'C:\\agent' -ItemType Directory -Force | Out-Null",
      "New-Item -Path 'C:\\agent\\_work' -ItemType Directory -Force | Out-Null",
      "New-Item -Path 'C:\\agent\\_work\\1' -ItemType Directory -Force | Out-Null",
      "New-Item -Path 'C:\\agent\\_work\\1\\s' -ItemType Directory -Force | Out-Null",
      "New-Item -Path 'C:\\agent\\_work\\1\\a' -ItemType Directory -Force | Out-Null"
    ]
  }

  # === PHASE 11: Optimize .NET Assemblies ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Run-NGen.ps1"]
  }

  # === PHASE 12: Finalize VM ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Finalize-VM.ps1"]
  }

  # === PHASE 13: Restart ===
  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  # === PHASE 14: Wait After Restart ===
  provisioner "powershell" {
    pause_before = "2m0s"
    inline       = ["Write-Host 'Waiting after restart...'", "Start-Sleep -Seconds 30"]
  }

  # === PHASE 15: Cleanup ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Cleanup-VM.ps1"]
  }

  # === PHASE 16: Sysprep ===
  provisioner "powershell" {
    inline = [
      "Write-Host 'Preparing for Sysprep...'",
      "if (Test-Path $Env:SystemRoot\\System32\\Sysprep\\unattend.xml) {",
      "  Remove-Item $Env:SystemRoot\\System32\\Sysprep\\unattend.xml -Force",
      "}"
    ]
  }
}