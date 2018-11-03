[cmdletbinding()]
param()
Push-Location
Set-Location $PSScriptRoot\..
.\Invoke-TestRunner.ps1 `
  -ApplicationName ROA `
  -Environment demo `
  -WorkingDirectory $PSScriptRoot\..\AppCode\ROA-demo\ `
  -TestCommand "npm run e2e-demo" `
  -FailureSlackChannel "roa-team-e2e" `
  -Verbose:$VerbosePreference
Pop-Location