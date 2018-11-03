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

function Get-FullPath {
  Param ([string] $path)
  if (!([System.IO.Path]::IsPathRooted($path))) {
    $path = Join-Path ($PWD) $path
  }
  return (([System.IO.Path]::GetFullPath($path)) -replace '[\\/]$','')
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

function Publish-BlobFile {
  param (
    [Parameter(Mandatory=$false)]
    [string]
    $uploadUrl = $env:TEST_RESULT_UPLOAD_URL,
    [Parameter(Mandatory=$true)]
    [string]
    $fileToUpload,
    [Parameter(Mandatory=$true)]
    [string]
    $environment,
    [Parameter(Mandatory=$true)]
    [string]
    $blobName
  )
  
  $blobContentType = switch ([System.IO.Path]::GetExtension($fileToUpload)) {
    ".html" { 'text/html' }
    ".png" { 'image/png' }
    ".json" { 'application/json' }
    ".js" { 'application/javascript' }
    Default { 'text/plain' }
  }

  Write-Verbose "Getting upload URL from $uploadUrl for /$environment/$blobName"
  $body = @{environment = $environment; filename = "$blobName"}
  $urlDest = (Invoke-RestMethod -Uri $UploadUrl -Body $body).url
  
  $webClient = New-Object System.Net.WebClient
  $webClient.Headers.Add('Content-Type', 'application/octet-stream')
  $webClient.Headers.Add('x-ms-version', '2017-04-17')
  $webClient.Headers.Add('x-ms-blob-type', 'BlockBlob')
  $webClient.Headers.Add('x-ms-blob-content-type', $blobContentType)
  Write-Verbose "Calling UploadFile with $urlDest, `"PUT`", $fileToUpload"
  $webClient.UploadFile($urlDest, "PUT", $fileToUpload)
  return ($urlDest -replace '\?.*','')
}
