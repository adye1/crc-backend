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

@description('Email address for alert notifications. Supplied from a GitHub secret, never committed. Empty skips the action group.')
param alertEmail string = ''

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
      functionAppScaleLimit: 2   // caps scale-out, limiting cost if the API is flooded
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

resource alertGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (!empty(alertEmail)) {
  name: 'ag-crc-alerts'
  location: 'global'
  properties: {
    groupShortName: 'crcalerts'
    enabled: true
    emailReceivers: [
      { name: 'owner', emailAddress: alertEmail, useCommonAlertSchema: true }
    ]
  }
}

var alertActions = !empty(alertEmail) ? [ { actionGroupId: alertGroup.id } ] : []

resource errorsAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-api-5xx'
  location: 'global'
  properties: {
    description: 'The visitor API returned server errors.'
    severity: 2
    enabled: true
    scopes: [ func.id ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        { name: 'Http5xx', criterionType: 'StaticThresholdCriterion', metricName: 'Http5xx', operator: 'GreaterThan', threshold: 0, timeAggregation: 'Total' }
      ]
    }
    actions: alertActions
  }
}

resource surgeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-api-request-surge'
  location: 'global'
  properties: {
    description: 'Unusually many requests: a popular page or a denial-of-wallet attempt.'
    severity: 3
    enabled: true
    scopes: [ func.id ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        { name: 'Requests', criterionType: 'StaticThresholdCriterion', metricName: 'Requests', operator: 'GreaterThan', threshold: 300, timeAggregation: 'Total' }
      ]
    }
    actions: alertActions
  }
}

resource latencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-api-latency'
  location: 'global'
  properties: {
    description: 'API responses are slower than normal.'
    severity: 3
    enabled: true
    scopes: [ func.id ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        { name: 'ResponseTime', criterionType: 'StaticThresholdCriterion', metricName: 'HttpResponseTime', operator: 'GreaterThan', threshold: 3, timeAggregation: 'Average' }
      ]
    }
    actions: alertActions
  }
}

output functionName string = func.name
output apiUrl string = 'https://${func.properties.defaultHostName}/api/visitors'
