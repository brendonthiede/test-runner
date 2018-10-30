properties {
  $FUNCTION_STORAGE_ACCOUNT_NAME
  $FUNCTION_STORAGE_BASE_URL
  $FUNCTION_APP_NAME
  $FUNCTION_APP_URL
}

# Default task includes Analyzing and Testing of script
task default -depends Publish

# Deploy resources assuming a connection already exists
task DeployIACConnected {
  Push-Location
  Set-Location "$PSScriptRoot"
  $DEPLOYMENT_OUTPUTS = (New-AzResourceDeployment -ResourceGroupName "test-results-prod-rg" --ResourceLocation "eastus" --TemplateFile .\autodeploy.json)

  $script:FUNCTION_STORAGE_ACCOUNT_NAME = $DEPLOYMENT_OUTPUTS.functionStorageAccountName.value
  $script:FUNCTION_STORAGE_BASE_URL = $DEPLOYMENT_OUTPUTS.functionStorageBlobBaseUrl.value -replace '/$', ''
  $script:FUNCTION_APP_NAME = $DEPLOYMENT_OUTPUTS.functionAppName.value
  $script:FUNCTION_APP_URL = "https://$($DEPLOYMENT_OUTPUTS.functionAppUri.value)"
  
  az storage cors add --methods OPTIONS PUT --origins '*' --exposed-headers '*' --allowed-headers '*' --services b --account-name $script:FUNCTION_STORAGE_ACCOUNT_NAME

  Pop-Location
}

# Creates a NuGet package with the desired contents
task Publish {
  Push-Location
  $functionsRoot = "$PSScriptRoot\..\TestRunner.Functions"
  $artifactFolder = "$functionsRoot\dist"
  $publishOut = "$artifactFolder\publish"
  $zipDestination = "$artifactFolder\TestRunner.Functions.zip"
  Set-Location "$functionsRoot"

  if (Test-path $artifactFolder) { Remove-Item $artifactFolder -Force -Recurse }
  dotnet publish --configuration Release --output $publishOut
  if ($LASTEXITCODE -ne 0) { Invoke-ErrorReport "Could not compile the Azure Functions" }

  Add-Type -assembly "system.io.compression.filesystem"
  [io.compression.zipfile]::CreateFromDirectory($publishOut, $zipDestination)

  Remove-Item $publishOut -Force -Recurse
  Pop-Location
}

function New-AzResourceDeployment {
  Param ([string] $ResourceGroupName, [string] $ResourceLocation, [string] $TemplateFile)
  $TIMESTAMP = (Get-Date).ToString("yyyyMMdd-HHmm")
  $DEPLOYMENT_NAME = "FirstServerlessAppDeployment$TIMESTAMP"
  az group create --name $ResourceGroupName --location $ResourceLocation --tag owner=devops
  if ($LASTEXITCODE -ne 0) { Invoke-ErrorReport "Could not create resource group" }
  $DEPLOYMENT_OUTPUTS = ((az group deployment create `
        --name $DEPLOYMENT_NAME `
        --resource-group $ResourceGroupName `
        --template-file $TemplateFile | ConvertFrom-Json).properties.outputs)
  if ($LASTEXITCODE -ne 0) { Invoke-ErrorReport "ARM template deployment error: $DEPLOYMENT_OUTPUTS" }

  # Wait for app to be ready for deployment
  $TIMEOUT = new-timespan -Minutes 5
  $STOP_WATCH = [diagnostics.stopwatch]::StartNew()
  $APP_READY = $False
  while (!$APP_READY -and $STOP_WATCH.elapsed -lt $TIMEOUT) {
    $WEB_APP = (az functionapp show -g $ResourceGroupName -n $DEPLOYMENT_OUTPUTS.functionAppName.value | ConvertFrom-Json)
    Write-Host $WEB_APP
    Write-Output $WEB_APP
    if ($WEB_APP.state -eq "Running" -and $WEB_APP.usageState -eq "Normal") {
      $APP_READY = $True
    }

    Start-Sleep -seconds 5
  }

  Return $DEPLOYMENT_OUTPUTS
}

