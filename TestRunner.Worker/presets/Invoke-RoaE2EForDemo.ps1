[cmdletbinding()]
param()
Push-Location
Set-Location $PSScriptRoot\..
.\Invoke-TestRunner.ps1 `
  -ApplicationName ROA `
  -Environment demo `
  -WorkingDirectory $PSScriptRoot\..\AppCode\ROA-demo\ `
  -TestCommand "npm run e2e-demo" `
  -FailureSlackChannel "testy-testy" `
  -Verbose:$VerbosePreference
Pop-Location