[cmdletbinding()]
param(
  # Name of the Application
  [Parameter(Mandatory = $true)]
  [string]
  $ApplicationName,

  # Name of the Application
  [Parameter(Mandatory = $true)]
  [string]
  [ValidateSet("dev", "demo", "staging", "prod")]
  $Environment,

  # URL to the Git repo
  [Parameter(Mandatory = $true)]
  [string]
  $GitUrl,

  # Specific revision of code to grab
  [Parameter(Mandatory = $false)]
  [string]
  $GitRevision = "",

  # Personal access token or Azure DevOps
  [Parameter(Mandatory = $false)]
  [string]
  $PersonalAccessToken = ""
)

Push-Location

if (!(Test-Path $PSScriptRoot\AppCode)) {
  mkdir $PSScriptRoot\AppCode
}
Set-Location $PSScriptRoot\AppCode

if ($PersonalAccessToken -ne "") {
  if (!($GitUrl -match '^https://.*')) {
    throw "Only HTTPS URLs are allowed with a Persaonl Access Token"
  }  
  $GitUrl = $GitUrl -replace '^https://', "https://Personal%20Access%20Token:$($PersonalAccessToken)@"
}

$TargetFolder = "$ApplicationName-$Environment"
$TempFolder = "$ApplicationName-$Environment-Temp"
$SwapFolder = "$ApplicationName-$Environment-Swap"

git clone $GitUrl $TempFolder

Set-Location $TempFolder
if ($GitRevision -ne "") {
  git fetch origin $GitRevision
  git checkout $GitRevision
}
npm install

if (Test-Path .\node_modules\.bin\webdriver-manager) {
  .\node_modules\.bin\webdriver-manager update
}

Set-Location $PSScriptRoot\AppCode
if (Test-Path $TargetFolder) {
  Move-Item $TargetFolder $SwapFolder
}

Move-Item $TempFolder $TargetFolder

Push-Location
Set-Location $TargetFolder
npm install

if (Test-Path .\node_modules\.bin\webdriver-manager) {
  .\node_modules\.bin\webdriver-manager update
}
Pop-Location

while ((Test-Path $SwapFolder)) {
  Remove-Item -Recurse -Force $SwapFolder
}

Pop-Location
