// packer {
//   required_plugins {
//     # https://github.com/rgl/packer-plugin-windows-update
//     windows-update = {
//       version = "0.14.1"
//       source  = "github.com/rgl/windows-update"
//     }
//   }
// }

# https://www.packer.io/plugins/builders/azure/arm
source "azure-arm" "vm" {
  skip_create_image                = false
  user_assigned_managed_identities = [var.sandbox.identityId] # optional
  async_resourcegroup_delete       = true
  vm_size                          = "Standard_D8s_v3" # default is Standard_A1
  # winrm options
  communicator   = "winrm"
  winrm_username = "packer"
  winrm_insecure = true
  winrm_use_ssl  = true
  os_type        = "Windows" # tells packer to create a certificate for WinRM connection
  # base image options (Azure Marketplace Images only)
  // image_publisher    = "microsoftwindowsdesktop"
  // image_offer        = "windows-ent-cpc"
  // image_sku          = "win11-22h2-ent-cpc-m365"

  image_publisher    = "microsoftvisualstudio"
  image_offer        = "visualstudioplustools"
  image_sku          = "vs-2022-ent-general-win11-m365-gen2"

  image_version      = "latest"
  use_azure_cli_auth = true
  # managed image options
  managed_image_name                = var.image.name
  managed_image_resource_group_name = var.gallery.resourceGroup
  # packer creates a temporary resource group
  subscription_id = var.sandbox.subscription
  // location                 = var.location
  // temp_resource_group_name = var.tempResourceGroup
  # OR use an existing resource group
  build_resource_group_name = var.sandbox.resourceGroup
  # optional use an existing key vault
  build_key_vault_name = var.sandbox.keyVault
  # optional use an existing virtual network
  virtual_network_name                = var.sandbox.virtualNetwork
  virtual_network_subnet_name         = var.sandbox.defaultSubnet
  virtual_network_resource_group_name = var.sandbox.virtualNetworkResourceGroup
  shared_image_gallery_destination {
    subscription         = var.gallery.subscription
    gallery_name         = var.gallery.name
    resource_group       = var.gallery.resourceGroup
    image_name           = var.image.name
    image_version        = var.image.version
    replication_regions  = var.image.replicaLocations
    storage_account_type = "Standard_LRS" # default is Standard_LRS
  }
}


build {
  sources = ["source.azure-arm.vm"]

  # Temporarily disable Auto-Logon
  # Our testing has shown that Windows 10 does not allow packer to run a Windows scheduled task until the admin user (packer) has logged into the system.
  # So we enable AutoAdminLogon and use packer's windows-restart provisioner to get the system into a good state to allow scheduled tasks to run.
  provisioner "powershell" {
    inline = [
      "Set-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon' -Name AutoAdminLogon -Value 1 -type String -ErrorAction Stop",
      "Set-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon' -Name DefaultUsername -Value ${build.User} -type String -ErrorAction Stop",
      "Set-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon' -Name DefaultPassword -Value ${build.Password} -type String -ErrorAction Stop"
    ]
  }

  provisioner "windows-restart" {
    # needed to get elevated script execution working
    restart_timeout = "30m"
    pause_before    = "2m"
  }

  # https://github.com/rgl/packer-plugin-windows-update
  // provisioner "windows-update" {
  // }

  ###BAKE###

  # Disable Auto-Logon that was enabled above
  provisioner "powershell" {
    inline = [
      "Remove-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon' -Name AutoAdminLogon -ErrorAction Stop",
      "Remove-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon' -Name DefaultUserName -ErrorAction Stop",
      "Remove-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon' -Name DefaultPassword -ErrorAction Stop",
    ]
  }

  # Generalize the image
  provisioner "powershell" {
    inline = [
      # Generalize the image
      "while ((Get-Service RdAgent -ErrorAction SilentlyContinue) -and ((Get-Service RdAgent).Status -ne 'Running')) { Start-Sleep -s 5 }",
      "while ((Get-Service WindowsAzureTelemetryService -ErrorAction SilentlyContinue) -and ((Get-Service WindowsAzureTelemetryService).Status -ne 'Running')) { Start-Sleep -s 5 }",
      "while ((Get-Service WindowsAzureGuestAgent -ErrorAction SilentlyContinue) -and ((Get-Service WindowsAzureGuestAgent).Status -ne 'Running')) { Start-Sleep -s 5 }",
      "Remove-Item $Env:SystemRoot\\system32\\Sysprep\\unattend.xml -Force -ErrorAction SilentlyContinue",
      # https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-command-line-options?view=windows-11
      "& $Env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /mode:vm /generalize /quiet /quit",
      "while ($true) { $imageState = (Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State).ImageState; Write-Output $imageState; if ($imageState -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { break }; Start-Sleep -s 5 }"
    ]
  }
}
