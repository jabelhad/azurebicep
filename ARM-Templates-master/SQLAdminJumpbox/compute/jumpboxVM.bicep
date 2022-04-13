param vmName string
param location string
param subnetRef string
param vmSize string = 'Standard_B2ms'
param osDiskType string = 'StandardSSD_LRS'
param adminUsername string = 'adm.infra.usr'
@secure()
param adminPassword string = 'P${uniqueString(newGuid())}x%'
param storeAdminPasswordInKeyVault bool = false
param sqlAdminKeyVaultName string
//param sqlAdminPassword string = 'P${uniqueString(resourceGroup().id)}-${uniqueString(subscription().id)}x!'
param patchMode string = 'AutomaticByOS'
param autoShutdownTimeZone string = 'US Mountain Standard Time'
param autoShutdownNotificationLocale string = 'en'

@description('Tags for deployed resources.')
param Tags object = {}

var nsgName = '${vmName}-nsg'
var nsgRules = [
  {
    name:'RDP'
    properties: {
        priority:300
        protocol:'Tcp'
        access:'Allow'
        direction:'Inbound'
        sourceAddressPrefix:'*'
        sourcePortRange:'*'
        destinationAddressPrefix:'*'
        destinationPortRange:'3389'
    }
  }
]

var nicName = '${vmName}-nic'

// Create the NIC for the VM
resource nic 'Microsoft.Network/networkInterfaces@2021-02-01' = {
  name: nicName
  location: location
  tags: Tags
  dependsOn: []
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetRef
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// Store the Sql Admin Password in Key Vault
// The individual deploying this ARM template must be an Owner or User Access Administrator over the Subscription
// in order to create a key within the key vault.
resource createAdminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = if (storeAdminPasswordInKeyVault) {
  name: '${sqlAdminKeyVaultName}/${vmName}'
  tags: Tags
  properties: {
    attributes: {}
    contentType: '${vmName} Sql Admin Password'
    value: adminPassword
  }  
}

// Create the SQL Admin Jumpbox VM(s)
resource createSqlAdminJumpboxVM 'Microsoft.Compute/virtualMachines@2021-03-01' = {
  name: vmName
  location: location
  tags: Tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
      }
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2019-Datacenter'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
        patchSettings: {
          enableHotpatching: false
          patchMode: patchMode
        }
      }
    }
    licenseType: 'Windows_Server'
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}
output adminUsername string = adminUsername

resource shutdownVM 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vmName}'
  location: location
  tags: Tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: '19:00'
    }
    timeZoneId: autoShutdownTimeZone
    targetResourceId: createSqlAdminJumpboxVM.id
    notificationSettings: {
      status: 'Disabled'
      notificationLocale: autoShutdownNotificationLocale
      timeInMinutes: 30
    }
  }  
}

// Constructing the PowerShell commands to execute once VM is running
resource cseInstallSMSS 'Microsoft.Compute/virtualMachines/extensions@2021-03-01' = {
  name: '${vmName}/InstallSSMS'
  location: location
  tags: Tags
  dependsOn: [
    createSqlAdminJumpboxVM
  ]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.7'
    autoUpgradeMinorVersion: true
    settings: {
      //  .\RRAS-Configuration.ps1 -localIP 172.1.0.4 -localSubnet "172.1.0.0/16" -peerPublicIP00 "20.150.153.222" -psk "rolightn3494" -peerPublicIP01 20.150.153.241
      //commandToExecute: 'powershell.exe Start-Process -Wait -PassThru -FilePath c:\\ssmsInstaller\\ssmsSetup.exe -ArgumentList """/install", "/quiet"""'
      commandToExecute: 'powershell.exe md c:\\ssmsInstaller -ErrorAction Ignore; powershell.exe Invoke-WebRequest -Uri https://aka.ms/ssmsfullsetup -OutFile c:\\ssmsInstaller\\ssmsSetup.exe -ErrorAction Ignore; powershell.exe Start-Process -Wait -PassThru -FilePath c:\\ssmsInstaller\\ssmsSetup.exe -ArgumentList """/install", "/quiet"""'
    } 
  }
}
