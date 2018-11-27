[CmdletBinding()]
param(
  [Parameter(Mandatory = $False)]
  [String]
  $EnvironmentName = "AzureCloud",

  [Parameter(Mandatory = $False)]
  [String]
  $SubscriptionName = "Visual Studio Enterprise",

  [Parameter(Mandatory = $False)]
  [String]
  $ResourceLocation = "eastus",

  [Parameter(Mandatory = $False)]
  [String]
  $ResourceGroupName = "test-results-rg",

  [Parameter(Mandatory = $False)]
  [Switch]
  $ExcludeInfrastructure,

  [Parameter(Mandatory = $False)]
  [Switch]
  $RebuildInfrastructure,

  [Parameter(Mandatory = $False)]
  [String]
  $TemplateFile = "$PSScriptRoot\autodeploy.json"
)

function Save-ShellAppearance {
  [Environment]::SetEnvironmentVariable("FOREGROUND_COLOR", [console]::ForegroundColor, "User")
  [Environment]::SetEnvironmentVariable("BACKGROUND_COLOR", [console]::BackgroundColor, "User")
}

function Reset-ShellAppearance {
  [console]::ForegroundColor = [Environment]::GetEnvironmentVariable("FOREGROUND_COLOR", "User")
  [console]::BackgroundColor = [Environment]::GetEnvironmentVariable("BACKGROUND_COLOR", "User")
}

function Write-ObjectError {
  Param ([object]$Details)
  if ($null -ne $Details) {
    Write-Verbose "Details type: $($Details.GetType().Name)"
    if ($Details.GetType().Name -eq "Object[]") {
      foreach ($Detail in $Details) {
        Write-ObjectError $Detail
      }
    }
    else {
      Write-Error "$Detail"
    }
  }
  else {
    Write-Verbose "No additional details provided"
  }
}

function Invoke-ErrorReport {
  Param ([string]$Message, [object]$Details)
  Reset-ShellAppearance
  Write-Error $Message
  Write-ObjectError $Details
  Pop-Location
  throw
}

function Connect-AzSubscription {
  Param ([string] $EnvironmentName, [string] $SubscriptionName)
  $ACCOUNT_INFO = (az account show | ConvertFrom-Json)
  Reset-ShellAppearance
  if ($ACCOUNT_INFO.environmentName -ne "$EnvironmentName" -or $ACCOUNT_INFO.name -ne "$SubscriptionName") {
    az cloud set --name "$EnvironmentName"
    az login
    Write-Verbose "Switching to $SubscriptionName"
    az account set --subscription "$SubscriptionName"
    if ($LASTEXITCODE -ne 0) { Invoke-ErrorReport "Could not connect to subscription '$SubscriptionName'" }
    $ACCOUNT_INFO = (az account show | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $ACCOUNT_INFO.environmentName -ne "$EnvironmentName" -or $ACCOUNT_INFO.name -ne "$SubscriptionName") { Invoke-ErrorReport "Could not connect to subscription '$SubscriptionName'" }
  }
  else {
    Write-Verbose "Already connected to $SubscriptionName"
  }
}

function New-AzResourceDeployment {
  Param ([string] $ResourceGroupName, [string] $ResourceLocation, [string] $TemplateFile)
  $TIMESTAMP = (Get-Date).ToString("yyyyMMdd-HHmm")
  $DEPLOYMENT_NAME = "TestRunnerDeployment$TIMESTAMP"
  Write-Verbose "Creating $ResourceGroupName"
  az group create --name "$ResourceGroupName" --location $ResourceLocation --tag owner=devops
  if ($LASTEXITCODE -ne 0) { Invoke-ErrorReport "Could not create resource group" }
  Write-Verbose "Deploying $TemplateFile to $ResourceGroupName"
  try {
    $RESULTS = (az group deployment create `
        --name $DEPLOYMENT_NAME `
        --resource-group "$ResourceGroupName" `
        --template-file $TemplateFile | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0) { Invoke-ErrorReport "ARM template deployment error: $DEPLOYMENT_OUTPUTS" }
    if ($RESULT.properties.provisioningState -eq "Succeeded") {
      $DEPLOYMENT_OUTPUTS = ($RESULTS.properties.outputs)
    }
    else {
      if ($RESULT.additionalProperties.error.code -eq "DeploymentFailed") {
        Invoke-ErrorReport "ARM template deployment error:" $RESULT.additionalProperties.error.details
      }
      else {
        Invoke-ErrorReport "ARM template deployment in provisioning state $($RESULT.properties.provisioningState)"
      }
    }
  }
  catch {
    Invoke-ErrorReport "ARM template deployment error"
  }

  # Wait for app to be ready for deployment
  $TIMEOUT = new-timespan -Minutes 5
  $STOP_WATCH = [diagnostics.stopwatch]::StartNew()
  $APP_READY = $False
  while (!$APP_READY -and $STOP_WATCH.elapsed -lt $TIMEOUT) {
    $WEB_APP = (az functionapp show -g $ResourceGroupName -n $DEPLOYMENT_OUTPUTS.functionAppName.value | ConvertFrom-Json)
    if ($WEB_APP.state -eq "Running" -and $WEB_APP.usageState -eq "Normal") {
      $APP_READY = $True
    }

    Start-Sleep -seconds 5
  }

  Return $DEPLOYMENT_OUTPUTS
}

Push-Location
$PROJECT_ROOT = "$PSScriptRoot\..\"
Set-Location $PROJECT_ROOT
Save-ShellAppearance

Connect-AzSubscription -EnvironmentName "$EnvironmentName" -SubscriptionName "$SubscriptionName"

if (!$ExcludeInfrastructure) {
  Write-Verbose "Deploying infrastructure"
  if ($RebuildInfrastructure) {
    Write-Verbose "Deleting $ResourceGroupName"
    az group delete --name "$ResourceGroupName" --yes
  }
  $DEPLOYMENT_OUTPUTS = New-AzResourceDeployment -ResourceGroupName $ResourceGroupName -ResourceLocation $ResourceLocation -TemplateFile $TemplateFile
  $FUNCTION_STORAGE_ACCOUNT_NAME = $DEPLOYMENT_OUTPUTS.functionStorageAccountName.value
  $FUNCTION_STORAGE_BASE_URL = $DEPLOYMENT_OUTPUTS.functionStorageBlobBaseUrl.value -replace '/$', ''
  $FUNCTION_APP_NAME = $DEPLOYMENT_OUTPUTS.functionAppName.value
  $FUNCTION_APP_URL = "https://$($DEPLOYMENT_OUTPUTS.functionAppUri.value)"
  Write-Verbose "Storage Account Name: $FUNCTION_STORAGE_ACCOUNT_NAME"
  Write-Verbose "Storage Account Base URL: $FUNCTION_STORAGE_BASE_URL"
  Write-Verbose "Functions App Name: $FUNCTION_APP_NAME"
  Write-Verbose "Functions App URL: $FUNCTION_APP_URL"
  if ($null -eq $FUNCTION_APP_NAME -or "" -eq $FUNCTION_APP_NAME) {
    Invoke-ErrorReport "FUNCTION_APP_NAME is empty. ARM template deployment likely failed."
    throw
  }
  az storage cors add --methods OPTIONS PUT --origins '*' --exposed-headers '*' --allowed-headers '*' --services b --account-name $FUNCTION_STORAGE_ACCOUNT_NAME
}
else {
  Write-Verbose "Assuming existing infrastructure"
  $FUNCTION_STORAGE_OBJECT = (az storage account list -g "$ResourceGroupName" | ConvertFrom-Json | Where-Object {$_.name -match '^serverless'})[0]
  $FUNCTION_STORAGE_ACCOUNT_NAME = $FUNCTION_STORAGE_OBJECT.name
  $FUNCTION_STORAGE_BASE_URL = $FUNCTION_STORAGE_OBJECT.primaryEndpoints.blob -replace '/$', ''
  $FUNCTION_APP_OBJECTS = (az functionapp list -g "$ResourceGroupName" | ConvertFrom-Json)
  $FUNCTION_APP_OBJECT = ($FUNCTION_APP_OBJECTS | Where-Object {$_.name -match '^test-results-'})[0]
  $FUNCTION_APP_NAME = $FUNCTION_APP_OBJECT.name
  $FUNCTION_APP_URL = "https://$($FUNCTION_APP_OBJECT.hostNames[0])"
  Write-Verbose "Storage Account Name: $FUNCTION_STORAGE_ACCOUNT_NAME"
  Write-Verbose "Storage Account Base URL: $FUNCTION_STORAGE_BASE_URL"
  Write-Verbose "Functions App Name: $FUNCTION_APP_NAME"
  Write-Verbose "Functions App URL: $FUNCTION_APP_URL"
}

Write-Verbose "Compiling Azure functions and packaging them for deployment"
.\scripts\build.ps1 -Task Publish -Verbose:$VerbosePreference

Write-Verbose "Deploying function to Azure"
az functionapp deployment source config-zip `
  --resource-group "$ResourceGroupName" `
  --name $FUNCTION_APP_NAME `
  --src ".\TestRunner.Functions\dist\TestRunner.Functions.zip"
if ($LASTEXITCODE -ne 0) { Invoke-ErrorReport "Could not deploy the Azure Functions" }

Reset-ShellAppearance

Write-Output "Site is ready at $FUNCTION_APP_URL/test-results"

Pop-Location