using 'main.bicep'

param location = 'eastus2'
param cosmosName = 'cosmos-crc-28411'
param functionStorageName = 'stfunc86912'
param functionAppName = 'func-crc-86960'
param planName = 'EastUS2LinuxDynamicPlan'
param logWorkspaceName = 'log-crc'
param appInsightsName = 'appi-crc'
param allowedOrigins = [
  'https://adamdye.dev'
  'https://stcrcfront99661.z13.web.core.windows.net'
]
