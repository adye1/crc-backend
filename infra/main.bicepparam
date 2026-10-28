using 'main.bicep'

param location = 'eastus2'
param cosmosName = 'cosmos-crc-28411'
param functionStorageName = 'stfunc86912'
param functionAppName = 'func-crc-86960'
param planName = 'EastUS2LinuxDynamicPlan'
param allowedOrigins = [
  'https://stcrcfront99661.z13.web.core.windows.net'
]
