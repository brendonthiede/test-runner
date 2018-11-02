[cmdletbinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]
  $Message,

  [Parameter(Mandatory = $true)]
  [string]
  $Channel,

  [Parameter(Mandatory = $false)]
  [string]
  $SlackWebHookUri = $env:SLACK_WEBHOOK_URI
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
