[cmdletbinding()]
param(
  # Directory to run tests from
  [Parameter(Mandatory = $true)]
  [string]
  $WorkingDirectory,

  # Test command to run
  [Parameter(Mandatory = $true)]
  [string]
  $TestCommand
)

function Send-PSSlackMessage {
  param(
    [Parameter(Mandatory = $true)]
    [string]
    $Message,

    [Parameter(Mandatory = $true)]
    [string]
    $Channel,

    [Parameter(Mandatory = $false)]
    [string]
    $SlackWebHookUri = [System.Environment]::GetEnvironmentVariable("SLACK_WEBHOOK_URI", "User")
  )

  if (!(Get-Command Send-SlackMessage)) {
    if (!(Get-Module PSSlack)) {
      Install-Module PSSlack -Scope CurrentUser
    }
    else {
      Import-Module PSSlack
    }
  }
  
  Send-SlackMessage `
    -Uri $SlackWebHookUri `
    -Parse full `
    -Text $Message `
    -Channel $Channel
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
  Write-Host "Tests passed"
}
else {
  Write-Error "Tests failed"
}

Exit $TestExitCode