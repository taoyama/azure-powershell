param (
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $ClusterName,

    [Parameter(Mandatory, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string] $ClusterRegion,

    [Parameter(Mandatory, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [string] $DatabaseName,

    [Parameter(Mandatory, Position = 3)]
    [ValidateNotNullOrEmpty()]
    [string] $TableName,

    [Parameter(Mandatory, Position = 4)]
    [ValidateNotNullOrEmpty()]
    [guid] $ServicePrincipalId,

    [Parameter(Mandatory, Position = 5)]
    [ValidateNotNullOrEmpty()]
    [string] $ServicePrincipalSecret,

    [Parameter(Mandatory, Position = 6)]
    [ValidateNotNullOrEmpty()]
    [guid] $ServicePrincipalTenantId
)

Import-Module "./tools/TestFx/Utilities/KustoUtilities.psd1" -Force
Import-KustoDataFromCsv -ClusterName $ClusterName -ClusterRegion $ClusterRegion -DatabaseName $DatabaseName -TableName $TableName -ServicePrincipalId $ServicePrincipalId -ServicePrincipalSecret $ServicePrincipalSecret -ServicePrincipalTenantId $ServicePrincipalTenantId
