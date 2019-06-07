[CmdletBinding()]
param (
  [Parameter(Mandatory = $false)]
  [string]
  $UploadUrl = $env:TEST_RESULT_UPLOAD_URL,
  [Parameter(Mandatory = $true)]
  [string]
  [ValidateSet("Passed", "Failed")]
  $TestStatus,
  [Parameter(Mandatory = $true)]
  [string]
  [ValidateSet("dev", "demo", "staging", "prod")]
  $Environment,
  [Parameter(Mandatory = $true)]
  [string]
  $TestResultsFolder,
  [Parameter(Mandatory = $true)]
  [string]
  $ApplicationName,
  [Parameter(Mandatory = $false)]
  [string]
  $ReportFilename = "report.html"
)

. $PSScriptRoot\lib\helpers.ps1

$datePrefix = (Get-Date -Format "yyyy-MM-dd")
$timePrefix = (Get-Date -Format "HH_mm_ss")
$blobName = "$datePrefix/$timeprefix,$TestStatus,$Environment,$ApplicationName,$ReportFilename"
Write-Verbose "TestResultsFolder: $TestResultsFolder"
$TestResultsFolder = Get-FullPath($TestResultsFolder)
$sourceFilePath = "$TestResultsFolder\$reportFilename"

if (!(Test-Path $TestResultsFolder)) {
  throw "Test results folder $TestResultsFolder could not be found"
}
if (!(Test-Path $sourceFilePath)) {
  throw "Test results report $sourceFilePath could not be found"
}

Write-Verbose "Publishing report to Azure storage"

Publish-BlobFile -uploadUrl $UploadUrl -fileToUpload $sourceFilePath -environment $Environment -blobName $blobName -Verbose:$VerbosePreference | Tee-Object -Variable ReportUrl

Write-Verbose "Publishing screenshots to Azure storage"
foreach ($image in (Get-ChildItem "$TestResultsFolder" -Filter "*.png")) {
  $blobName = "$datePrefix/$($image.Name)"
  $sourceFilePath = "$TestResultsFolder\$($image.Name)"
  Publish-BlobFile -uploadUrl $UploadUrl -fileToUpload $sourceFilePath -environment $Environment -blobName $blobName -Verbose:$VerbosePreference
}

return $ReportUrl
