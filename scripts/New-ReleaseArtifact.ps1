Push-Location
$functionsRoot = "$PSScriptRoot\..\TestRunner.Functions"
$artifactFolder = "$functionsRoot\dist"
$publishOut = "$artifactFolder\publish"
$zipDestination = "$artifactFolder\TestRunner.Functions.zip"
Set-Location "$functionsRoot"

if (Test-path $artifactFolder) { Remove-Item $artifactFolder -Force -Recurse }
dotnet publish --configuration Release --output $publishOut
if ($LASTEXITCODE -ne 0) { Invoke-ErrorReport "Could not compile the Azure Functions" }

Add-Type -assembly "system.io.compression.filesystem"
[io.compression.zipfile]::CreateFromDirectory($publishOut, $zipDestination)

Remove-Item $publishOut -Force -Recurse
Pop-Location
