function Save-ShellAppearance {
  [Environment]::SetEnvironmentVariable("FOREGROUND_COLOR", [console]::ForegroundColor, "User")
  [Environment]::SetEnvironmentVariable("BACKGROUND_COLOR", [console]::BackgroundColor, "User")
}

function Reset-ShellAppearance {
  [console]::ForegroundColor = [Environment]::GetEnvironmentVariable("FOREGROUND_COLOR", "User")
  [console]::BackgroundColor = [Environment]::GetEnvironmentVariable("BACKGROUND_COLOR", "User")
}

function Assert-True {
  Param ([bool] $Value, [string] $ErrorMessage)
  if (!$Value) {
    Invoke-ErrorReport -Message "$ErrorMessage"
  }
}

function Invoke-ErrorReport {
  Param ([string] $Message)
  Reset-ShellAppearance
  Pop-Location
  throw "$Message"
}

function Connect-AzSubscription {
  Param ([string] $EnvironmentName, [string] $SubscriptionName)
  $ACCOUNT_INFO = (az account show | ConvertFrom-Json)
  Reset-ShellAppearance
  if ($ACCOUNT_INFO.environmentName -ne "$EnvironmentName" -or $ACCOUNT_INFO.name -ne "$SubscriptionName") {
    az cloud set --name "$EnvironmentName"
    az login
    az account set --subscription "$SubscriptionName"
    Assert-True -Value ($LASTEXITCODE -eq 0) -ErrorMessage "Could not connect to subscription '$SubscriptionName'"
    $ACCOUNT_INFO = (az account show | ConvertFrom-Json)
    Assert-True -Value  ($LASTEXITCODE -eq 0 -and $ACCOUNT_INFO.environmentName -eq "$EnvironmentName" -and $ACCOUNT_INFO.name -eq "$SubscriptionName") `
      -ErrorMessage "Could not connect to subscription '$SubscriptionName'"
  }
}

function New-AzResourceDeployment {
  Param ([string] $ResourceGroupName, [string] $ResourceLocation, [string] $TemplateFile)

  $TIMESTAMP = (Get-Date).ToString("yyyyMMdd-HHmm")
  $DEPLOYMENT_NAME = "FirstServerlessAppDeployment$TIMESTAMP"

  az group create --name "$ResourceGroupName" --location "$ResourceLocation" --tag owner=devops
  Assert-True -Value ($LASTEXITCODE -eq 0) -ErrorMessage "Could not create resource group"
  $DEPLOYMENT_OUTPUTS = ((az group deployment create `
        --name $DEPLOYMENT_NAME `
        --resource-group $ResourceGroupName `
        --template-file $TemplateFile | ConvertFrom-Json).properties.outputs)
  Assert-True -Value ($LASTEXITCODE -eq 0) -ErrorMessage "ARM template deployment error: $DEPLOYMENT_OUTPUTS"

  # Wait for app to be ready for deployment
  $TIMEOUT = new-timespan -Minutes 5
  $STOP_WATCH = [diagnostics.stopwatch]::StartNew()
  $APP_READY = $False
  while (!$APP_READY -and $STOP_WATCH.elapsed -lt $TIMEOUT) {
    $WEB_APP = (az functionapp show -g $ResourceGroupName -n $DEPLOYMENT_OUTPUTS.functionAppName.value | ConvertFrom-Json)
    if ($WEB_APP.state -eq "Running" -and $WEB_APP.availabilityState -eq "Normal" -and $WEB_APP.usageState -eq "Normal") {
      $APP_READY = $True
    }

    Start-Sleep -seconds 5
  }

  Return $DEPLOYMENT_OUTPUTS
}

function New-FunctionAppDeployment {
  Param ([string] $ResourceGroupName, [string] $FunctionAppName, [string] $ZipFile)

  az functionapp deployment source config-zip `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --src $ZipFile
  Assert-True -Value ($LASTEXITCODE -eq 0) -ErrorMessage "Could not deploy the Azure Functions"
}
