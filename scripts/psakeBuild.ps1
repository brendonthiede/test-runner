. $PSScriptRoot\..\TestRunner.Worker\lib\helpers.ps1

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
  $WORKER_SOURCE_FOLDER = $WorkerSourceFolder;
  $WORKER_DESTINATION_FOLDER = $WorkerDestinationFolder;
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

# Deploy the worker scripts
task DeployWorker {
  $WORKER_SOURCE_FOLDER = Get-FullPath($WORKER_SOURCE_FOLDER) -replace '[\\/]$', ''
  $WORKER_DESTINATION_FOLDER = Get-FullPath($WORKER_DESTINATION_FOLDER) -replace '[\\/]$', ''
  $SourceShortName = [System.IO.Path]::GetFileName("$WORKER_SOURCE_FOLDER")
  $Incremental = $false
  if (!(Test-Path "$WORKER_DESTINATION_FOLDER")) {
    Write-Verbose "Creating directory $WORKER_DESTINATION_FOLDER"
    mkdir -Force "$WORKER_DESTINATION_FOLDER"
  }

  if (Test-Path "$WORKER_DESTINATION_FOLDER\$SourceShortName") {
    $Incremental = $true
    Write-Verbose "Previously existing $WORKER_DESTINATION_FOLDER\$SourceShortName is being moved to $WORKER_DESTINATION_FOLDER\$SourceShortName.Old"
    Move-Item -Force "$WORKER_DESTINATION_FOLDER\$SourceShortName" "$WORKER_DESTINATION_FOLDER\$SourceShortName.Old"
  }

  Copy-Item -Force "$WORKER_SOURCE_FOLDER\*" "$WORKER_DESTINATION_FOLDER\$SourceShortName" -Verbose:$VerbosePreference
  Copy-Item -Recurse -Force "$WORKER_SOURCE_FOLDER\lib" "$WORKER_DESTINATION_FOLDER\$SourceShortName\" -Verbose:$VerbosePreference
  Copy-Item -Recurse -Force "$WORKER_SOURCE_FOLDER\presets" "$WORKER_DESTINATION_FOLDER\$SourceShortName\" -Verbose:$VerbosePreference

  if ($Incremental -and (Test-Path "$WORKER_DESTINATION_FOLDER\$SourceShortName.Old\AppCode")) {
    Write-Verbose "Copying existing AppCode from $WORKER_DESTINATION_FOLDER\$SourceShortName.Old\AppCode to $WORKER_DESTINATION_FOLDER\$SourceShortName\"
    Move-Item -Force "$WORKER_DESTINATION_FOLDER\$SourceShortName.Old\AppCode" "$WORKER_DESTINATION_FOLDER\$SourceShortName\"
  }

  $TimeOut = new-timespan -Minutes 5
  $StopWatch = [diagnostics.stopwatch]::StartNew()
  while ((Test-Path "$WORKER_DESTINATION_FOLDER\$SourceShortName.Old") -and $StopWatch.elapsed -lt $TimeOut) {
    Write-Verbose "Removing files from $WORKER_DESTINATION_FOLDER\$SourceShortName.Old"
    Remove-Item -Recurse -Force "$WORKER_DESTINATION_FOLDER\$SourceShortName.Old"
  }
}

# Creates a zip file for deploying the function app
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
