[cmdletbinding()]
param()
Push-Location
Set-Location $PSScriptRoot\..
.\Invoke-TestRunner.ps1 `
  -ApplicationName ROA `
  -Environment dev `
  -WorkingDirectory $PSScriptRoot\..\AppCode\ROA-dev\ `
  -TestCommand "npm run e2e-dev" `
  -FailureSlackChannel "testy-testy" `
  -Verbose:$VerbosePreference
Pop-Location