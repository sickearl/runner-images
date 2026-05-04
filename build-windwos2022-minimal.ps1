
# 1. Chocolatey
# Set-ExecutionPolicy Bypass -Scope Process -Force
# iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# winget install "Windows Assessment and Deployment Kit" --override "/quiet /features OptionId.DeploymentTools"

#choco install packer
# OR
#winget install Hashicorp.Packer

# Assicurati di essere nella directory corretta
cd images\windows

# Init (scarica plugin)
packer init templates/windows-2022-minimal.pkr.hcl

# Validate
packer validate templates/windows-2022-minimal.pkr.hcl

# Se validation OK, builda
$env:PACKER_LOG=1
$env:PACKER_LOG_PATH="packer-build.log"

packer build templates/windows-2022-minimal.pkr.hcl