Push-Location
Set-Location $PSScriptRoot

$ResourceGroupName = "test-results-prod-rg"
$Location = "eastus"
$Tags = @{owner = "devops"}

$resourceGroup = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (!$resourceGroup) {
  New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -Tags $Tags
}

Test-AzureRmResourceGroupDeployment `
  -ResourceGroupName $ResourceGroupName `
  -TemplateFile ".\autodeploy.json"

Pop-Location
