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
  # default = "file:///D:/virtual machine/SERVER_EVAL_x64FRE_en-us.iso"
  default = "file:///C:/Devel/local pipeline/SERVER_EVAL_x64FRE_en-us.iso"
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

  # === FASE 0a: Crea struttura cartelle (elevated) ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    inline = [
      "New-Item -Path '${var.image_folder}' -ItemType Directory -Force | Out-Null",
      "New-Item -Path '${var.image_folder}\\scripts\\build' -ItemType Directory -Force | Out-Null",
      "New-Item -Path '${var.image_folder}\\scripts\\helpers' -ItemType Directory -Force | Out-Null",
      "New-Item -Path '${var.image_folder}\\scripts\\tests' -ItemType Directory -Force | Out-Null",
      "New-Item -Path '${var.image_folder}\\scripts\\docs-gen' -ItemType Directory -Force | Out-Null",
      "New-Item -Path '${var.image_folder}\\tests' -ItemType Directory -Force | Out-Null",
      "Write-Host 'Directories created'"
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

  # Copia tests nel path atteso dagli script
  provisioner "file" {
    destination = "${var.image_folder}\\tests\\"
    source      = "${path.root}/../scripts/tests/"
  }

  # === FASE 0c: Copia toolset.json ===
  provisioner "file" {
    destination = "${var.image_folder}\\toolset.json"
    source      = var.toolset_file_path
  }

  # === FASE 0d: Installa moduli PowerShell e profilo globale (elevated) ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    inline = [
      # ImageHelpers
      "$modulePath = 'C:\\Program Files\\WindowsPowerShell\\Modules\\ImageHelpers'",
      "New-Item -Path $modulePath -ItemType Directory -Force | Out-Null",
      "Copy-Item '${var.image_folder}\\scripts\\helpers\\*' $modulePath -Recurse -Force",

      # Helpers (tests)
      "$testModulePath = 'C:\\Program Files\\WindowsPowerShell\\Modules\\Helpers'",
      "New-Item -Path $testModulePath -ItemType Directory -Force | Out-Null",
      "Copy-Item '${var.image_folder}\\scripts\\tests\\Helpers.psm1' \"$testModulePath\\Helpers.psm1\" -Force",

      # Profilo globale - importa moduli ad ogni sessione
      "$profilePath = 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\profile.ps1'",
      "$profileContent = \"Import-Module ImageHelpers -Force -ErrorAction SilentlyContinue`nImport-Module Helpers -Force -ErrorAction SilentlyContinue\"",
      "Set-Content -Path $profilePath -Value $profileContent -Encoding UTF8",

      # Verifica
      ". $profilePath",
      "if (Get-Command Invoke-PesterTests -ErrorAction SilentlyContinue) { Write-Host 'OK: Invoke-PesterTests available' } else { Write-Host 'WARNING: Invoke-PesterTests not found' }"
    ]
  }

  # === FASE 0e: Imposta IMAGE_FOLDER come variabile d'ambiente globale ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    inline = [
      "[Environment]::SetEnvironmentVariable('IMAGE_FOLDER', '${var.image_folder}', 'Machine')",
      "$env:IMAGE_FOLDER = '${var.image_folder}'",
      "Write-Host \"IMAGE_FOLDER set to: ${var.image_folder}\""
    ]
  }
  
  # === FASE 0f: Setta TEMP_DIR e installa Pester ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    inline = [
      # TEMP_DIR usato da InstallHelpers.ps1
      "New-Item -Path 'C:\\Temp' -ItemType Directory -Force | Out-Null",
      "[Environment]::SetEnvironmentVariable('TEMP_DIR', 'C:\\Temp', 'Machine')",
      "$env:TEMP_DIR = 'C:\\Temp'",
      "Write-Host 'TEMP_DIR set'",

      # Pester 5 richiesto da Helpers.psm1 per i test
      "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force",
      "Install-Module Pester -Force -SkipPublisherCheck -MinimumVersion 5.0",
      "Import-Module Pester -Force",
      "Write-Host 'Pester installed'"
    ]
  }

  # === FASE 1: Configura Windows (script Microsoft) ===
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

# === FASE 2: Chocolatey (inline, evita TEMP_DIR issues) ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    inline = [
      "Write-Host 'Installing Chocolatey...'",
      "$env:TEMP_DIR = 'C:\\Temp'",
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072",
      "iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))",
      "$env:PATH = $env:PATH + ';C:\\ProgramData\\chocolatey\\bin'",
      "[Environment]::SetEnvironmentVariable('PATH', $env:PATH, 'Machine')",
      "choco feature enable -n allowGlobalConfirmation",
      "Write-Host 'Chocolatey installed'"
    ]
  }

  # === FASE 3: PowerShell 7 (via Chocolatey, evita checksum issues) ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    inline = [
      "Write-Host 'Installing PowerShell 7...'",
      "choco install powershell-core -y",
      "Write-Host 'PowerShell 7 installed'"
    ]
  }

  # === FASE 4: Git (via script Microsoft, funziona bene) ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Install-Git.ps1"]
  }
  
# === FASE 4b: Aggiorna root certificates (best effort) ===
#  provisioner "powershell" {
#    elevated_user     = var.winrm_username
#    elevated_password = var.winrm_password
#    inline = [
#      "Write-Host 'Updating root certificates (best effort)...'",
#      "certutil -generateSSTFromWU C:\\Temp\\roots.sst 2>$null",
#      "if (Test-Path C:\\Temp\\roots.sst) {",
#      "  certutil -addstore -f root C:\\Temp\\roots.sst",
#      "  Remove-Item C:\\Temp\\roots.sst -Force",
#      "  Write-Host 'Root certificates updated'",
#      "} else {",
#      "  Write-Host 'WARNING: Root certificates update skipped (timeout)'",
#      "}"
#    ]
#  }

  # === FASE 5: Visual Studio Build Tools (via script Microsoft) ===
#  provisioner "powershell" {
#    elevated_user     = var.winrm_username
#    elevated_password = var.winrm_password
#    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
#    scripts           = ["${path.root}/../scripts/build/Install-VisualStudio.ps1"]
#  }

# === FASE 5: Visual Studio Build Tools (inline, bypassa VisualStudioHelpers) ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    inline = [
      "Write-Host 'Downloading VS Build Tools...'",
      "$url = 'https://aka.ms/vs/17/release/vs_BuildTools.exe'",
      "Invoke-WebRequest -Uri $url -OutFile 'C:\\Temp\\vs_BuildTools.exe' -UseBasicParsing",
      "",
      "Write-Host 'Installing VS Build Tools...'",
      "$args = @(",
      "  '--quiet', '--norestart', '--nocache', '--wait',",
      "  '--add', 'Microsoft.VisualStudio.Workload.MSBuildTools',",
      "  '--add', 'Microsoft.VisualStudio.Workload.NetCoreBuildTools',",
      "  '--add', 'Microsoft.Net.Component.4.8.1.SDK',",
      "  '--add', 'Microsoft.Net.Component.4.8.SDK',",
      "  '--add', 'Microsoft.Net.Component.4.7.2.SDK',",
      "  '--add', 'Microsoft.Net.Component.4.7.2.TargetingPack',",
      "  '--add', 'Microsoft.Net.Component.4.6.2.TargetingPack',",
      "  '--add', 'Microsoft.VisualStudio.Component.NuGet.BuildTools',",
      "  '--add', 'Microsoft.VisualStudio.Component.Roslyn.Compiler',",
      "  '--add', 'Microsoft.Component.MSBuild'",
      ")",
      "$process = Start-Process -FilePath 'C:\\Temp\\vs_BuildTools.exe' -ArgumentList $args -Wait -PassThru",
      "if ($process.ExitCode -notin @(0, 3010)) {",
      "  Write-Host \"VS installation failed with exit code: $($process.ExitCode)\"",
      "  exit $process.ExitCode",
      "}",
      "Write-Host 'VS Build Tools installed successfully'"
    ]
  }

  # === FASE 6: .NET SDK (via Chocolatey, evita checksum issues) ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    inline = [
      "Write-Host 'Installing .NET Framework Dev Packs...'",
      "choco install netfx-4.8.1-devpack -y",
      "choco install netfx-4.8-devpack -y",
      "choco install netfx-4.7.2-devpack -y",
      "Write-Host '.NET Framework Dev Packs installed'"
    ]
  }

  # === FASE 7: NuGet CLI ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    inline = [
      "Write-Host 'Installing NuGet CLI...'",
      "choco install nuget.commandline -y",
      "Write-Host 'NuGet installed'"
    ]
  }

  # === FASE 8: Toolset (via script Microsoft) ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Install-Toolset.ps1"]
  }

  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
    scripts           = ["${path.root}/../scripts/build/Configure-Toolset.ps1"]
  }

#  # === FASE 9: Native Images (.NET assembly optimization) ===
#  provisioner "powershell" {
#    elevated_user     = var.winrm_username
#    elevated_password = var.winrm_password
#    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}"]
#    scripts           = ["${path.root}/../scripts/build/Install-NativeImages.ps1"]
#  }

  # === FASE 10: Struttura directory agent ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    inline = [
      "New-Item -Path 'C:\\agent\\_work\\1\\s' -ItemType Directory -Force | Out-Null",
      "New-Item -Path 'C:\\agent\\_work\\1\\a' -ItemType Directory -Force | Out-Null",
      "Write-Host 'Agent directories created'"
    ]
  }

  # === FASE 11: Restart ===
  provisioner "windows-restart" {
    restart_timeout       = "30m"
    restart_check_command = "powershell -command \"& {Write-Output 'restarted'}\""
  }

  # === FASE 12: Post-restart - NO environment_vars, NO use_pwsh ===
  provisioner "powershell" {
    pause_before      = "3m0s"
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    # ← NO environment_vars (causa forward slash)
    # ← NO use_pwsh (richiede CET)
    scripts           = ["${path.root}/../scripts/build/Install-WindowsUpdatesAfterReboot.ps1"]
  }

  # === FASE 13: Cleanup ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    # ← NO environment_vars
    scripts           = ["${path.root}/../scripts/build/Invoke-Cleanup.ps1"]
  }

  # === FASE 14: Sysprep ===
  provisioner "powershell" {
    elevated_user     = var.winrm_username
    elevated_password = var.winrm_password
    inline = [
      "if (Test-Path $Env:SystemRoot\\System32\\Sysprep\\unattend.xml) {",
      "  Remove-Item $Env:SystemRoot\\System32\\Sysprep\\unattend.xml -Force",
      "}"
    ]
  }
}