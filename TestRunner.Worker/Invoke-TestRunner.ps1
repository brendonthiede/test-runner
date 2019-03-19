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

  # Directory to run tests from
  [Parameter(Mandatory = $true)]
  [string]
  $WorkingDirectory,

  # Test command to run
  [Parameter(Mandatory = $true)]
  [string]
  $TestCommand,

  # If provided, this channel will get a message if there is a failure
  [Parameter(Mandatory = $false)]
  [string]
  $FailureSlackChannel = ""
)

. $PSScriptRoot\lib\helpers.ps1

$WorkingDirectory = Get-FullPath($WorkingDirectory)
Write-Verbose "WorkingDirectory: $WorkingDirectory"

if (!(Test-Path $WorkingDirectory)) {
  throw "$WorkingDirectory does not exist"
}

Push-Location

Set-Location $WorkingDirectory

$TestExitCode = 0

try {
  Invoke-Expression "$TestCommand"
  $TestExitCode = $LASTEXITCODE
}
catch {
  $TestExitCode = 1
}
finally {
  Pop-Location
}

if ($TestExitCode -eq 0) {
  $TestStatus = "Passed"
}
else {
  $TestStatus = "Failed"
}

Write-Verbose "Tests $TestStatus"

Push-Location
Set-Location "$PSScriptRoot"

.\Publish-TestResults.ps1 -TestStatus $TestStatus -Environment $Environment -TestResultsFolder "$WorkingDirectory\testresults" -ApplicationName $ApplicationName -Verbose:$VerbosePreference
.\Update-TestResultsList.ps1 -Environment $Environment -Verbose:$VerbosePreference | Tee-Object -Variable ReportListUrl
$ReportListUrl = $ReportListUrl[$ReportListUrl.length - 1]

if ($TestStatus -eq "Failed" -and $FailureSlackChannel -ne "") {
  $Message = "$ApplicationName tests failed in $Environment`: $ReportListUrl"
  .\Send-PSSlackMessage.ps1 -Message $Message -Channel $FailureSlackChannel
}

Remove-Item -Recurse -Force "$WorkingDirectory\testresults"

Pop-Location

Exit $TestExitCode