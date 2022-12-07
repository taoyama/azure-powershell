[CmdletBinding(DefaultParameterSetName = "ByScriptFile")]
param (
    [Parameter(Mandatory)]
    [bool] $UseWindowsPowerShell,

    [Parameter(Mandatory, ParameterSetName = "ByScriptFile")]
    [ValidateNotNullOrEmpty()]
    [string] $ScriptPath,

    [Parameter(Mandatory, ParameterSetName = "ByScriptBlock")]
    [ValidateNotNullOrEmpty()]
    [string] $Script
)

if ($UseWindowsPowerShell) {
    $process = "powershell"
}
else {
    $process = "dotnet tool run pwsh"
}

switch ($PSCmdlet.ParameterSetName) {
    "ByScriptFile" {
        Invoke-Expression "$process -NoLogo -NoProfile -NonInteractive -File $ScriptPath"
    }
    "ByScriptBlock" {
        Invoke-Expression "$process -NoLogo -NoProfile -NonInteractive -Command $Script"
    }
}
