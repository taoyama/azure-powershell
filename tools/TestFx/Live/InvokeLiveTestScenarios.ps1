param (
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $BuildId,

    [Parameter(Mandatory, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string] $OSVersion,

    [Parameter(Mandatory, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [string] $PSVersion
)

Get-ChildItem -Path LiveTests -Directory -Recurse | ForEach-Object { Get-ChildItem -Path (Join-Path -Path $_.FullName -ChildPath TestLiveScenarios.ps1) -File } | ForEach-Object {
    $moduleName = [regex]::match($_.FullName, "[\/|\\]src[\/|\\](?<ModuleName>[a-zA-Z]+)[\/|\\]").Groups["ModuleName"].Value
    if ($PSVersion -eq "latest") {
        $PSVersion = (Get-Variable -Name PSVersionTable).Value.PSVersion.ToString()
    }
    Import-Module "./tools/TestFx/Assert.ps1" -Force
    Import-Module "./tools/TestFx/Live/LiveTestUtilities.psd1" -ArgumentList $moduleName, $BuildId, $OSVersion, $PSVersion -Force
    . $_
}
