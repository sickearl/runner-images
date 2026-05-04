# windows-2022-minimal-dotnet.pkr.hcl

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
  # default = "file:///C:/Devel/local pipeline/SERVER_EVAL_x64FRE_en-us.iso"
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
  # default = "C:\\image"
  default = "D:\\image"
}

variable "toolset_file_path" {
  type    = string
  default = "./toolsets/toolset-2022-minimal.json"
}

# ============================================================================
# SOURCE
# ============================================================================

source "hyperv-iso" "vm" {
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  vm_name               = var.vm_name
  generation            = 2
  switch_name           = "Default Switch"
  enable_secure_boot    = false
  enable_dynamic_memory = true
  memory                = 8192
  cpus                  = 4
  disk_size             = 81920
  disk_block_size       = 1

  output_directory = var.output_directory

  boot_wait    = "1s"
  boot_command = ["<enter>"]

  cd_files = [
    "${path.root}/../answer_files/Autounattend.xml",
    "${path.root}/../scripts/provisioners/setup-winrm.ps1"
  ]

  communicator   = "winrm"
  winrm_username = var.winrm_username
  winrm_password = var.winrm_password
  winrm_timeout  = "12h"
  winrm_use_ssl  = false

  shutdown_command = "C:\\Windows\\System32\\Sysprep\\Sysprep.exe /generalize /oobe /shutdown /quiet"
  shutdown_timeout = "1h"
}

# ============================================================================
# BUILD
# ============================================================================

build {
  sources = ["source.hyperv-iso.vm"]

  # === PHASE 1: Crea cartella immagine ===
  provisioner "powershell" {
    inline = [
      "New-Item -Path '${var.image_folder}' -ItemType Directory -Force | Out-Null"
    ]
  }

  # === PHASE 2: Copia toolset.json nella VM ===
  provisioner "file" {
    destination = "${var.image_folder}\\toolset.json"
    source      = var.toolset_file_path
  }

  # === PHASE 3: Configurazione base Windows ===
  provisioner "powershell" {
    scripts = ["${path.root}/../scripts/build/Configure-WindowsDefender.ps1"]
  }

  provisioner "powershell" {
    scripts = ["${path.root}/../scripts/build/Configure-PowerShell.ps1"]
  }

  provisioner "powershell" {
    scripts = ["${path.root}/../scripts/build/Configure-DynamicPort.ps1"]
  }

  provisioner "powershell" {
    scripts = ["${path.root}/../scripts/build/Configure-System.ps1"]
  }

  provisioner "powershell" {
    scripts = ["${path.root}/../scripts/build/Configure-SystemEnvironment.ps1"]
  }

  # === PHASE 4: Windows Features (.NET Framework incluso) ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-WindowsFeatures.ps1"]
  }

  # === PHASE 5: PowerShell 7 ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-PowershellCore.ps1"]
  }

  # === PHASE 6: Chocolatey ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-Chocolatey.ps1"]
  }

  # === PHASE 7: Git ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-Git.ps1"]
  }

  # === PHASE 8: Visual Studio Build Tools ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-VisualStudio.ps1"]
  }

  # === PHASE 9: .NET SDK ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-DotnetSDK.ps1"]
  }

  # === PHASE 10: Toolset (legge toolset.json) ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-Toolset.ps1"]
  }

  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Configure-Toolset.ps1"]
  }

  # === PHASE 11: Native Images (.NET assembly optimization) ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-NativeImages.ps1"]
  }

  # === PHASE 12: Crea struttura directory agent ===
  provisioner "powershell" {
    inline = [
      "New-Item -Path 'C:\\agent\\_work\\1\\s' -ItemType Directory -Force | Out-Null",
      "New-Item -Path 'C:\\agent\\_work\\1\\a' -ItemType Directory -Force | Out-Null"
    ]
  }

  # === PHASE 13: Restart ===
  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  # === PHASE 14: Windows Updates post-restart ===
  provisioner "powershell" {
    pause_before      = "2m0s"
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Install-WindowsUpdatesAfterReboot.ps1"]
  }

  # === PHASE 15: Cleanup ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    scripts           = ["${path.root}/../scripts/build/Invoke-Cleanup.ps1"]
  }

  # === PHASE 16: Sysprep ===
  provisioner "powershell" {
    inline = [
      "if (Test-Path $Env:SystemRoot\\System32\\Sysprep\\unattend.xml) {",
      "  Remove-Item $Env:SystemRoot\\System32\\Sysprep\\unattend.xml -Force",
      "}"
    ]
  }
}