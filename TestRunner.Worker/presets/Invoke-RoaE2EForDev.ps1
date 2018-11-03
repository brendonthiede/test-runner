[cmdletbinding()]
param()
Push-Location
Set-Location $PSScriptRoot\..
.\Invoke-TestRunner.ps1 `
  -ApplicationName ROA `
  -Environment dev `
  -WorkingDirectory $PSScriptRoot\..\AppCode\ROA-dev\ `
  -TestCommand "npm run e2e-dev" `
  -FailureSlackChannel "roa-team-e2e" `
  -Verbose:$VerbosePreference
Pop-Location