targetScope = 'resourceGroup'

@description('Region for the Function App, its storage, and Cosmos DB')
param location string = resourceGroup().location

@description('Origins allowed to call the API (CORS)')
param allowedOrigins array

param cosmosName string
param functionStorageName string
param functionAppName string
param planName string
param logWorkspaceName string
param appInsightsName string

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logWorkspaceName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    workspaceCapping: { dailyQuotaGb: json('0.1') }   // cost guard for a hobby project
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
    IngestionMode: 'LogAnalytics'
  }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: [
      { name: 'EnableTable' }
      { name: 'EnableServerless' }
    ]
    locations: [
      { locationName: location, failoverPriority: 0, isZoneRedundant: false }
    ]
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    minimalTlsVersion: 'Tls12'
  }
}

resource visitorsTable 'Microsoft.DocumentDB/databaseAccounts/tables@2024-05-15' = {
  parent: cosmos
  name: 'visitors'
  properties: {
    resource: { id: 'visitors' }
  }
}

resource funcStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: functionStorageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  kind: 'functionapp'
  sku: { name: 'Y1', tier: 'Dynamic' }
  properties: { reserved: true }
}

var storageConn = 'DefaultEndpointsProtocol=https;AccountName=${funcStorage.name};AccountKey=${funcStorage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
var cosmosConn = 'DefaultEndpointsProtocol=https;AccountName=${cosmos.name};AccountKey=${cosmos.listKeys().primaryMasterKey};TableEndpoint=https://${cosmos.name}.table.cosmos.azure.com:443/;'

resource func 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Python|3.12'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      cors: { allowedOrigins: allowedOrigins }
      appSettings: [
        { name: 'AzureWebJobsStorage', value: storageConn }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'COSMOS_TABLE_CONNECTION', value: cosmosConn }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
      ]
    }
  }
  dependsOn: [ visitorsTable ]
}

output functionName string = func.name
output apiUrl string = 'https://${func.properties.defaultHostName}/api/visitors'
