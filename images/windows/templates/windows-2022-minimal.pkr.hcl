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
  default = "file:///C:/Devel/local pipeline/SERVER_EVAL_x64FRE_en-us.iso"
  # default = "file:///D:/virtual machine/SERVER_EVAL_x64FRE_en-us.iso"

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
  # default = "D:\\image"
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
  generation            = 1
  switch_name           = "Default Switch"  
  enable_dynamic_memory = true
  memory                = 8192
  cpus                  = 4
  disk_size             = 81920
  disk_block_size       = 1

  output_directory = var.output_directory

  boot_wait    = "5s"
  boot_command = ["<enter>"]

  cd_files = [
    "${path.root}/../answer_files/Autounattend.xml"    
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

  # === FASE 0a: Crea struttura cartelle ===
  provisioner "powershell" {
    inline = [
      "New-Item -Path '${var.image_folder}' -ItemType Directory -Force | Out-Null",
      "New-Item -Path '${var.image_folder}\\scripts\\build' -ItemType Directory -Force | Out-Null",
      "New-Item -Path '${var.image_folder}\\scripts\\helpers' -ItemType Directory -Force | Out-Null",
      "New-Item -Path '${var.image_folder}\\scripts\\tests' -ItemType Directory -Force | Out-Null",
      "New-Item -Path '${var.image_folder}\\scripts\\docs-gen' -ItemType Directory -Force | Out-Null",
	  "New-Item -Path '${var.image_folder}\\tests' -ItemType Directory -Force | Out-Null"  
    ]
  }

  # === FASE 0b: Copia TUTTI gli script ===
  provisioner "file" {
    destination = "${var.image_folder}\\scripts\\build\\"
    source      = "${path.root}/../scripts/build/"
  }

  provisioner "file" {
    destination = "${var.image_folder}\\scripts\\helpers\\"
    source      = "${path.root}/../scripts/helpers/"
  }

  provisioner "file" {
    destination = "${var.image_folder}\\scripts\\tests\\"
    source      = "${path.root}/../scripts/tests/"
  }

  provisioner "file" {
    destination = "${var.image_folder}\\scripts\\docs-gen\\"
    source      = "${path.root}/../scripts/docs-gen/"
  }
  
    # === FASE 0b-extra: Copia tests anche nel path atteso dagli script ===
  provisioner "file" {
    destination = "${var.image_folder}\\tests\\"
    source      = "${path.root}/../scripts/tests/"
  }

  # === FASE 0c: Copia toolset.json ===
  provisioner "file" {
    destination = "${var.image_folder}\\toolset.json"
    source      = var.toolset_file_path
  }

   # === FASE 0d: Configura profilo PowerShell globale ===
  provisioner "powershell" {
    inline = [
      "$modulePath = 'C:\\Program Files\\WindowsPowerShell\\Modules\\ImageHelpers'",
      "New-Item -Path $modulePath -ItemType Directory -Force | Out-Null",
      "Copy-Item '${var.image_folder}\\scripts\\helpers\\*' $modulePath -Recurse -Force",

      "$testModulePath = 'C:\\Program Files\\WindowsPowerShell\\Modules\\Helpers'",
      "New-Item -Path $testModulePath -ItemType Directory -Force | Out-Null",
      "Copy-Item '${var.image_folder}\\scripts\\tests\\Helpers.psm1' \"$testModulePath\\Helpers.psm1\" -Force",

      "$profilePath = 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\profile.ps1'",
      "$profileContent = \"Import-Module ImageHelpers -Force -ErrorAction SilentlyContinue`nImport-Module Helpers -Force -ErrorAction SilentlyContinue\"",
      "Set-Content -Path $profilePath -Value $profileContent -Encoding UTF8",

      ". $profilePath",
      "if (Get-Command Invoke-PesterTests -ErrorAction SilentlyContinue) { Write-Host 'OK: Invoke-PesterTests available' } else { Write-Host 'WARNING: Invoke-PesterTests not found' }"
    ]
  }

  # === FASE 0e: Imposta IMAGE_FOLDER come variabile d'ambiente globale ===
  provisioner "powershell" {
    inline = [
      "[Environment]::SetEnvironmentVariable('IMAGE_FOLDER', '${var.image_folder}', 'Machine')",
      "$env:IMAGE_FOLDER = '${var.image_folder}'",
      "Write-Host \"IMAGE_FOLDER set to: $env:IMAGE_FOLDER\""
    ]
  }

  # === FASE 1: Configure Windows ===
  provisioner "powershell" {
    environment_vars = [
      "IMAGE_VERSION=minimal-dotnet",
      "IMAGE_FOLDER=${var.image_folder}"
    ]
    scripts = ["${path.root}/../scripts/build/Configure-WindowsDefender.ps1"]
  }

  provisioner "powershell" {
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts          = ["${path.root}/../scripts/build/Configure-DynamicPort.ps1"]
  }

  provisioner "powershell" {
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts          = ["${path.root}/../scripts/build/Configure-PowerShell.ps1"]
  }

  provisioner "powershell" {
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts          = ["${path.root}/../scripts/build/Configure-System.ps1"]
  }

  provisioner "powershell" {
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts          = ["${path.root}/../scripts/build/Configure-SystemEnvironment.ps1"]
  }

  # === FASE 2: Windows Features ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Install-WindowsFeatures.ps1"]
  }

  # === FASE 3: PowerShell 7 ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Install-PowershellCore.ps1"]
  }

  # === FASE 4: Chocolatey ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Install-Chocolatey.ps1"]
  }

  # === FASE 5: Git ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Install-Git.ps1"]
  }

  # === FASE 6: Visual Studio Build Tools ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Install-VisualStudio.ps1"]
  }

  # === FASE 7: .NET SDK ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Install-DotnetSDK.ps1"]
  }

  # === FASE 8: Toolset ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Install-Toolset.ps1"]
  }

  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Configure-Toolset.ps1"]
  }

  # === FASE 9: Native Images ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Install-NativeImages.ps1"]
  }

  # === FASE 10: Agent directories ===
  provisioner "powershell" {
    inline = [
      "New-Item -Path 'C:\\agent\\_work\\1\\s' -ItemType Directory -Force | Out-Null",
      "New-Item -Path 'C:\\agent\\_work\\1\\a' -ItemType Directory -Force | Out-Null",
      "Write-Host 'Agent directories created'"
    ]
  }

  # === FASE 11: Restart ===
  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  # === FASE 12: Post-restart updates ===
  provisioner "powershell" {
    pause_before      = "2m0s"
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Install-WindowsUpdatesAfterReboot.ps1"]
  }

  # === FASE 13: Cleanup ===
  provisioner "powershell" {
    elevated_password = var.winrm_password
    elevated_user     = var.winrm_username
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Invoke-Cleanup.ps1"]
  }

  # === FASE 14: Sysprep ===
  provisioner "powershell" {
    inline = [
      "if (Test-Path $Env:SystemRoot\\System32\\Sysprep\\unattend.xml) {",
      "  Remove-Item $Env:SystemRoot\\System32\\Sysprep\\unattend.xml -Force",
      "}"
    ]
  }
}