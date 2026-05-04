# Assicurati di essere nella directory corretta
cd C:\Devel\pipeline-agent\runner-images\images\windows

# Init (scarica plugin)
packer init templates/windows-2022-minimal-dotnet.pkr.hcl

# Validate
packer validate templates/windows-2022-minimal-dotnet.pkr.hcl

# Se validation OK, builda
$env:PACKER_LOG=1
$env:PACKER_LOG_PATH="packer-build.log"

packer build templates/windows-2022-minimal-dotnet.pkr.hcl