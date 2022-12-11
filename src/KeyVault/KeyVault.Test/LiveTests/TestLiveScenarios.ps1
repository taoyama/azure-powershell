Write-Host "Test KeyVault live scenarios"

Invoke-LiveTestScenario -Name "KeyVault.Create KeyVault Test" -Description "Test create KeyVault" -ScenarioScript `
{
    param ($rg)

    $rgName = $rg.ResourceGroupName
    $vaultLocation = "westus"
    $vaultName = New-LiveTestResourceName

    $kv = Get-AzKeyVault -VaultName $vaultName -ResourceGroupName $rgName
    if ($null -eq $kv) {
        New-AzKeyVault -Name $vaultName -ResourceGroupName $rgName -Location $vaultLocation
    }
    $got = Get-AzKeyVault -VaultName $vaultName -ResourceGroupName $rgName

    Assert-NotNull $got
    Assert-AreEqual $got.Location $vaultLocation
    Assert-AreEqual $got.ResourceGroupName $rgName
    Assert-AreEqual $got.VaultName $vaultName

    $got = Get-AzKeyVault -VaultName $vaultName

    Assert-NotNull $got
    Assert-AreEqual $got.Location $vaultLocation
    Assert-AreEqual $got.ResourceGroupName $rgName
    Assert-AreEqual $got.VaultName $vaultName
}

Invoke-LiveTestScenario -Name "KeyVault.Delete KeyVault Test" -Description "Test delete KeyVault" -ResourceGroupLocation "eastus" -ScenarioScript `
{
    param ($rg)

    $rgName = $rg.ResourceGroupName
    $vaultLocation = "westus"
    $vaultName = New-LiveTestResourceName

    New-AzKeyVault -ResourceGroupName $rgname -VaultName $vaultName -Location $vaultLocation
    Remove-AzKeyVault -VaultName $vaultName -Force

    $deletedVault = Get-AzKeyVault -ResourceGroupName $rgName -VaultName $vaultName
    Assert-Null $deletedVault

    # purge deleted vault
    Remove-AzKeyVault -ResourceGroupName $rgName -VaultName $vaultName -Location $vaultLocation -InRemovedState -Force

    # Test piping
    New-AzKeyVault -ResourceGroupName $rgname -VaultName $vaultName -Location $vaultLocation

    Get-AzKeyVault -ResourceGroupName $rgname -VaultName $vaultName | Remove-AzKeyVault -Force

    $deletedVault = Get-AzKeyVault -ResourceGroupName $rgName -VaultName $vaultName
    Assert-Null $deletedVault
}
