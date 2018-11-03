[CmdletBinding()]
param (
  [Parameter(Mandatory = $false)]
  [string]
  $StorageUrl = "https://testresultswq5cipeihi3us.blob.core.windows.net",
  [Parameter(Mandatory = $false)]
  [string]
  $UploadUrl = $env:TEST_RESULT_UPLOAD_URL,
  [Parameter(Mandatory = $true)]
  [string]
  [ValidateSet("dev", "demo", "staging", "prod")]
  $Environment
)

. $PSScriptRoot\lib\helpers.ps1

[System.Collections.ArrayList]$Reports = New-Object System.Collections.ArrayList
$today = (Get-Date)

Write-Verbose "Pulling last 3 days worth of results"
for ($i = 0; $i -lt 3; $i++) {
  $prefix = $today.AddDays($i).ToString("yyyy-MM-dd")
  $listUrl = "$StorageUrl/$Environment`?restype=container&comp=list&prefix=$prefix"
  $rawList = Invoke-RestMethod -Uri $listUrl
  $asXml = [xml]($rawList -replace "^[^<]*<", "<")
  $htmlBlobs = ($asXml.EnumerationResults.Blobs.Blob).Where( {$_.Name -match ".*\.html$"})

  foreach ($blob in $htmlBlobs) {
    $name = $blob.Name
    $dateVal = ($name -replace '(.*)/([^\/]+)', '$1')
    $nameParts = ($name -replace '(.*)/([^\/]+)', '$2') -split ","
    $timeVal = $nameParts[0] -replace '_', ':'
    $testStatus = $nameParts[1]
    $environment = $nameParts[2]
    $applicationName = $nameParts[3]
    $shortName = $nameParts[4]
    $url = $blob.Url

    ($Reports.Add(
        @{name            = $name;
          date            = $dateVal;
          time            = $timeVal;
          timestamp       = "$($dateVal)T$($timeVal)";
          testStatus      = $testStatus;
          environment     = $environment;
          applicationName = $applicationName;
          shortName       = $shortName;
          url             = $url
        })) | Out-Null
  }
}

$blobName = "reportlist.json"
$fileName = "$PSScriptRoot\$blobName"

$Reports | ConvertTo-Json | Tee-Object -Variable reportJson | Set-Content -Path $fileName
Write-Verbose "reportJson:`n$reportJson"

$sourceFilePath = Get-FullPath($fileName)
Write-Verbose "Publishing reportlist JavaScript to Azure storage"
Write-Verbose "sourceFilePath: $sourceFilePath"
Write-Verbose "UploadUrl: $UploadUrl"
Publish-BlobFile -uploadUrl $UploadUrl -fileToUpload $sourceFilePath -environment $Environment -blobName $blobName -Verbose:$VerbosePreference

$blobName = "reportlist.html"
$fileName = "$PSScriptRoot\$blobName"

Write-Verbose "Publishing reportlist HTML to Azure storage"
$sourceFilePath = Get-FullPath($fileName)
$ReportUrl = (Publish-BlobFile -uploadUrl $UploadUrl -fileToUpload $sourceFilePath -environment $Environment -blobName $blobName -Verbose:$VerbosePreference)

Write-Verbose "ReportUrl: $ReportUrl"

$ReportUrl