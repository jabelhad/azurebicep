@description('Name of new or existing vnet to which Azure Bastion should be deployed')
param vnetName string = 'vnet01'

@description('IP prefix for available addresses in vnet address space')
param vnetIpPrefix string = '10.1.0.0/16'

@description('Specify whether to provision new vnet or deploy to existing vnet')
@allowed([
  'new'
  'existing'
])
param vnetNewOrExisting string = 'existing'

@description('Specify whether to provision new vnet or deploy to existing vnet')
@allowed([
  'new'
  'existing'
])
param vnetSubnetNewOrExisting string = 'existing'

@description('Bastion subnet IP prefix MUST be within vnet IP prefix address space')
param bastionSubnetIpPrefix string = '10.1.1.0/27'

@description('Name of Azure Bastion resource')
param bastionHostName string

@description('Azure region for Bastion and virtual network')
param location string = resourceGroup().location

@description('Tags for deployed resources.')
param Tags object = {}

var publicIpAddressName = '${bastionHostName}-pip'
var bastionSubnetName = 'AzureBastionSubnet'

resource publicIp 'Microsoft.Network/publicIPAddresses@2021-03-01' = {
  name: publicIpAddressName
  location: location
  tags: Tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// if vnetNewOrExisting == 'new', create a new vnet and subnet
resource newVirtualNetwork 'Microsoft.Network/virtualNetworks@2021-03-01' = if (vnetNewOrExisting == 'new') {
  name: vnetName
  location: location
  tags: Tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetIpPrefix
      ]
    }
    subnets: [
      {
        name: bastionSubnetName
        properties: {
          addressPrefix: bastionSubnetIpPrefix
        }
      }
    ]
  }
}

// if vnetNewOrExisting == 'existing', reference an existing vnet and create a new subnet under it
resource existingVirtualNetwork 'Microsoft.Network/virtualNetworks@2021-03-01' existing = if (vnetNewOrExisting == 'existing') {
  name: vnetName
}
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-03-01' = if (vnetSubnetNewOrExisting == 'new') {
  parent: existingVirtualNetwork
  name: bastionSubnetName
  properties: {
    addressPrefix: bastionSubnetIpPrefix
  }
}

// Reference an existing Azure Bastion Subnet
resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-03-01' existing = if (vnetSubnetNewOrExisting == 'existing'){
  name: '${vnetName}/${bastionSubnetName}'
}

resource bastionHost 'Microsoft.Network/bastionHosts@2021-03-01' = {
  name: bastionHostName
  location: location
  tags: Tags
  dependsOn: [
    newVirtualNetwork
    existingVirtualNetwork
  ]
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: (vnetSubnetNewOrExisting == 'new') ? subnet.id : privateEndpointSubnet.id
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}
