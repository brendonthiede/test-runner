[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)]
    [ValidateSet("DeployFullConnected", "DeployFunctionsConnected", "DeployIACConnected", "Publish")]
    [string[]]
    $Task = 'Publish'
)

# Verify that we have the Azure CLI installed
if (!(Get-Command az) -or (az --version)[0].split().split('(').split('.')[2] -ne 2) {
  throw 'You need to install v2 of the Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-windows'
}

# Verify that we have PackageManagement module installed
if (!(Get-Command Install-Module)) {
  throw 'PackageManagement is not installed. You need PowerShell 5+ or https://www.microsoft.com/en-us/download/details.aspx?id=51451'
}

# Verify that our testing utilities are installed.
if (!(Get-Module -Name AzureRM -ListAvailable)) {
    Write-Output "Installing AzureRM PowerShell module"
    Install-Module -Name AzureRM -Force -Scope CurrentUser
}
if (!(Get-Module -Name psake -ListAvailable)) {
    Write-Output "Installing Psake PowerShell module"
    Install-Module -Name Psake -Force -Scope CurrentUser
}

# Ensure that all testing modules are at the required minimum version
if (((Get-Module -Name AzureRM -ListAvailable)[0].Version.Major) -lt 5 -or (((Get-Module -Name AzureRM -ListAvailable)[0].Version.Major) -eq 5 -and ((Get-Module -Name AzureRM -ListAvailable)[0].Version.Minor) -lt 2)) {
    Write-Output "Upgrading AzureRM PowerShell module"
    Update-Module -Name AzureRM -SkipPublisherCheck -Force -Scope CurrentUser
}
Import-Module Psake
if (((Get-Module -Name Psake).Version.Major) -lt 4) {
    Write-Output "Upgrading Psake PowerShell module"
    Update-Module -Name Psake -SkipPublisherCheck -Force -Scope CurrentUser
}

$azureCLIVersion = (az --version)[0].split().split('(').split(')')[2]

$azureRMVersion = (Get-Module -Name AzureRM -ListAvailable)[0].Version
$azureRMMajorVersion = $azureRMVersion.Major
$azureRMMinorVersion = $azureRMVersion.Minor
$azureRMBuildVersion = $azureRMVersion.Build

$psakeVersion = (Get-Module -Name Psake).Version
$psakeMajorVersion = $psakeVersion.Major
$psakeMinorVersion = $psakeVersion.Minor
$psakeBuildVersion = $psakeVersion.Build

Write-Output "Current tool versions:"
Write-Output "  Azure CLI:  $azureCLIVersion"
Write-Output "  AzureRM:    $azureRMMajorVersion.$azureRMMinorVersion.$azureRMBuildVersion"
Write-Output "  Psake:      $psakeMajorVersion.$psakeMinorVersion.$psakeBuildVersion"
Write-Output ""

. $PSScriptRoot\..\TestRunner.Worker\lib\helpers.ps1
Save-ShellAppearance
Invoke-psake -buildFile "$PSScriptRoot\psakeBuild.ps1" -taskList $Task -Verbose:$VerbosePreference
Reset-ShellAppearance
