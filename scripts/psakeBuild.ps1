. .\helpers\helpers.ps1

properties {
  $FUNCTIONS_ROOT = "$PSScriptRoot\..\TestRunner.Functions";
  $ARTIFACT_FOLDER = "$FUNCTIONS_ROOT\dist";
  $PUBLISH_OUT = "$ARTIFACT_FOLDER\publish";
  $ZIP_DESTINATION = "$ARTIFACT_FOLDER\TestRunner.Functions.zip";
  $RESOURCE_GROUP_NAME = "test-results-prod-rg";
  $RESOURCE_GROUP_LOCATION = "eastus";
  $ARM_TEMPLATE = "$PSScriptRoot\autodeploy.json"
  $FUNCTION_STORAGE_ACCOUNT_NAME;
  $FUNCTION_STORAGE_BASE_URL;
  $FUNCTION_APP_NAME;
  $FUNCTION_APP_URL;
}

# Default task includes Analyzing and Testing of script
task default -depends Publish

# Deploy infrastructure and Azure Functions assuming a connection already exists
task DeployFullConnected -depends DeployIACConnected, DeployFunctionsConnected {
}

# Deploy Azure Functions assuming a connection already exists
task DeployFunctionsConnected -depends Publish {
  New-FunctionAppDeployment -ResourceGroupName $RESOURCE_GROUP_NAME -FunctionAppName $FUNCTION_APP_NAME -ZipFile $ZIP_DESTINATION
}

# Deploy resources assuming a connection already exists
task DeployIACConnected {
  $DEPLOYMENT_OUTPUTS = (New-AzResourceDeployment -ResourceGroupName $RESOURCE_GROUP_NAME -ResourceLocation $RESOURCE_GROUP_LOCATION -TemplateFile $ARM_TEMPLATE)

  $script:FUNCTION_STORAGE_ACCOUNT_NAME = $DEPLOYMENT_OUTPUTS.functionStorageAccountName.value
  $script:FUNCTION_STORAGE_BASE_URL = $DEPLOYMENT_OUTPUTS.functionStorageBlobBaseUrl.value -replace '/$', ''
  $script:FUNCTION_APP_NAME = $DEPLOYMENT_OUTPUTS.functionAppName.value
  $script:FUNCTION_APP_URL = "https://$($DEPLOYMENT_OUTPUTS.functionAppUri.value)"
  
  az storage cors add --methods OPTIONS PUT --origins '*' --exposed-headers '*' --allowed-headers '*' --services b --account-name $script:FUNCTION_STORAGE_ACCOUNT_NAME
}

# Creates a NuGet package with the desired contents
task Publish {
  Push-Location
  Set-Location "$FUNCTIONS_ROOT"

  if (Test-path $ARTIFACT_FOLDER) { Remove-Item $ARTIFACT_FOLDER -Force -Recurse }
  dotnet publish --configuration Release --output $PUBLISH_OUT
  if ($LASTEXITCODE -ne 0) { Invoke-ErrorReport "Could not compile the Azure Functions" }

  Add-Type -assembly "system.io.compression.filesystem"
  [io.compression.zipfile]::CreateFromDirectory($PUBLISH_OUT, $ZIP_DESTINATION)

  Remove-Item $PUBLISH_OUT -Force -Recurse
  Pop-Location
}
