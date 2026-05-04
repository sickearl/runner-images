@'
# setup-winrm.ps1
# Configura WinRM per comunicazione con Packer

Write-Host "Configuring WinRM..."

# Abilita WinRM
Enable-PSRemoting -Force -SkipNetworkProfileCheck
winrm quickconfig -q
winrm quickconfig -transport:http

# Configura WinRM
winrm set winrm/config '@{MaxTimeoutms="7200000"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="2048"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service '@{MaxConcurrentOperationsPerUser="12000"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'

# Firewall
netsh advfirewall firewall add rule name="WinRM-HTTP" dir=in localport=5985 protocol=TCP action=allow
netsh advfirewall firewall add rule name="WinRM-HTTPS" dir=in localport=5986 protocol=TCP action=allow

# Disabilita UAC per Packer
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -PropertyType DWord -Value 1 -Force

# Restart WinRM
Restart-Service winrm -Force
Set-Service winrm -StartupType Automatic

Write-Host "WinRM configured successfully"
'@ | Out-File -FilePath "scripts\provisioners\setup-winrm.ps1" -Encoding UTF8

Write-Host "✅ setup-winrm.ps1 creato"