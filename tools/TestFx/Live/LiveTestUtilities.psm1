# ----------------------------------------------------------------------------------
# Copyright Microsoft Corporation
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------------------------------------------------------------

param (
    [Parameter(Mandatory, Position = 0)]
    [Alias("ModuleName")]
    [ValidateNotNullOrEmpty()]
    [string] $Name,

    [Parameter(Mandatory, Position = 1)]
    [ValidateSet("PSGallery", "Local", "Dev", IgnoreCase = $false, ErrorMessage = "Invalid value for parameter Source.")]
    [string] $Source = "Dev"
)

dynamicparam {
    switch ($Source) {
        "Local" {
            $localParams = [RuntimeDefinedParameterDictionary]::new()
            $locationParam = [RuntimeDefinedParameter]::new(
                "RepoLocation",
                [string],
                [Attribute[]]@(
                    [Parameter]@{ Mandatory = $true; Position = 1 }
                    [ValidateNotNullOrEmpty]::new()
                    [ValidateScript]::new({ Test-Path -LiteralPath $_ -PathType Container })
                )
            )
            $localParams.Add($locationParam.Name, $locationParam)
            $localParams
        }
    }
}

process {
    New-Variable -Name ResourceGroupPrefix -Value "azpsliverg" -Scope Script -Option Constant
    New-Variable -Name ResourcePrefix -Value "azpslive" -Scope Script -Option Constant
    New-Variable -Name StorageAccountPrefix -Value "azpslivesa" -Scope Script -Option Constant

    New-Variable -Name CommandMaxRetryCount -Value 3 -Scope Script -Option Constant
    New-Variable -Name CommandDelay -Value 10 -Scope Script -Option Constant
    New-Variable -Name ScenarioMaxRetryCount -Value 5 -Scope Script -Option Constant
    New-Variable -Name ScenarioMaxDelay -Value 60 -Scope Script -Option Constant
    New-Variable -Name ScenarioDelay -Value 5 -Scope Script -Option Constant

    New-Variable -Name RepoRootDirectory -Value ($PSScriptRoot | Split-Path | Split-Path | Split-Path) -Scope Script -Option Constant
    New-Variable -Name ArtifactsDirectory -Value (Join-Path -Path $script:RepoRootDirectory -ChildPath "artifacts") -Scope Script -Option Constant
    New-Variable -Name LiveTestRootDirectory -Value (Join-Path -Path $script:ArtifactsDirectory -ChildPath "LiveTestsAnalysis") -Scope Script -Option Constant
    New-Variable -Name LiveTestRawDirectory -Value (Join-Path -Path $script:LiveTestRootDirectory -ChildPath "Raw") -Scope Script -Option Constant
    New-Variable -Name LiveTestRawCsvFile -Value (Join-Path -Path $script:LiveTestRawDirectory -ChildPath "Az.$Name.csv") -Scope Script -Option Constant

    Import-Module ($PSScriptRoot | Split-Path | Join-Path -ChildPath "Assert.ps1") -Force

    function Initialize-LiveTestModule {
        [CmdletBinding()]
        [OutputType([void])]
        param (
            [Parameter(Mandatory, Position = 0)]
            [Alias("ModuleName")]
            [ValidateNotNullOrEmpty()]
            [string] $Name
        )

        if (!(Test-Path -LiteralPath $script:LiveTestRootDirectory -PathType Container)) {
            New-Item -Path $script:LiveTestRootDirectory -ItemType Directory
            New-Item -Path $script:LiveTestRawDirectory -ItemType Directory
        }

        ({} | Select-Object "Name", "Description", "StartDateTime", "EndDateTime", "IsSuccess", "Error" | ConvertTo-Csv -NoTypeInformation)[0] | Out-File -LiteralPath $script:LiveTestRawCsvFile -Force
    }

    function New-LiveTestRandomName {
        [CmdletBinding()]
        [OutputType([string])]
        param ()

        $alphanumerics = "0123456789abcdefghijklmnopqrstuvwxyz"
        $randomName = $alphanumerics[(Get-Random -Maximum 10)]
        for ($i = 0; $i -lt 9; $i ++) {
            $randomName += $alphanumerics[(Get-Random -Maximum $alphanumerics.Length)]
        }

        $randomName
    }

    function New-LiveTestResourceGroupName {
        [CmdletBinding()]
        [OutputType([string])]
        param ()

        $rgPrefix = $script:ResourceGroupPrefix
        $rgName = New-LiveTestRandomName

        $rgFullName = "$rgPrefix$rgName"
        $rgFullName
    }

    function New-LiveTestResourceGroup {
        [CmdletBinding()]
        param (
            [Parameter(Position = 0)]
            [Alias("ResourceGroupName")]
            [ValidateNotNullOrEmpty()]
            [ValidateScript({ $_ -match "^$script:ResourceGroupPrefix\d[a-zA-Z0-9]{9}$" }, ErrorMessage = "Invalid value for parameter Name")]
            [string] $Name = (New-LiveTestResourceGroupName),

            [Parameter(Position = 1)]
            [ValidateNotNullOrEmpty()]
            [string] $Location = "westus"
        )

        $rg = Invoke-LiveTestCommand -Command { New-AzResourceGroup -Name $Name -Location $Location }
        $rg
    }

    function New-LiveTestResourceName {
        [CmdletBinding()]
        [OutputType([string])]
        param ()

        $rPrefix = $script:ResourcePrefix
        $rName = New-LiveTestRandomName

        $rFullName = "$rPrefix$rName"
        $rFullName
    }

    function New-LiveTestStorageAccountName {
        [CmdletBinding()]
        [OutputType([string])]
        param ()

        $saPrefix = $script:StorageAccountPrefix
        $saName = New-LiveTestRandomName

        $saFullName = "$saPrefix$saName"
        $saFullName
    }

    function Invoke-LiveTestCommand {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory, ValueFromPipeline)]
            [ValidateNotNullOrEmpty()]
            [scriptblock] $Command
        )

        $cmdRetryCount = 0

        do {
            try {
                $cmdResult = Invoke-Command -ScriptBlock $Command -ErrorAction Stop
                $cmdResult
                break
            }
            catch {
                if ($cmdRetryCount -le $script:CommandMaxRetryCount) {
                    Write-Warning "Error occurred when executing command $Command. Live test will retry automatically in $script:CommandMaxRetryCount seconds."
                    Start-Sleep -Seconds $script:CommandDelay
                    $cmdRetryCount++
                    Write-Host "Retrying #$cmdRetryCount to execute command $Command."
                }
                else {
                    throw "Failed to execute command $Command after retrying for $script:CommandMaxRetryCount time(s)."
                }
            }
        }
        while ($true)
    }

    function Invoke-LiveTestScenario {
        [CmdletBinding()]
        [OutputType([bool])]
        param (
            [Parameter(Mandatory, Position = 0)]
            [ValidateNotNullOrEmpty()]
            [string] $Name,

            [Parameter()]
            [ValidateNotNullOrEmpty()]
            [string] $Description,

            [Parameter()]
            [ValidateNotNullOrEmpty()]
            [string] $ResourceGroupLocation,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [scriptblock] $ScenarioScript
        )

        if (!(Test-Path -LiteralPath $script:LiveTestRawCsvFile -PathType Leaf -ErrorAction SilentlyContinue)) {
            throw "Error occurred when initializing live tests. The csv file was not found."
        }

        try {
            $scnCsvData = [PSCustomObject]@{
                Name          = $Name
                Description   = $Description
                StartDateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
                EndDateTime   = $null
                IsSuccess     = $true
                Error         = ""
            }

            $scnResourceGroupName = New-LiveTestResourceGroupName
            $scnResourceGroupLocation = "westus"
            if ($PSBoundParameters.ContainsKey("ResourceGroupLocation")) {
                $scnResourceGroupLocation = $ResourceGroupLocation
            }
            New-LiveTestResourceGroup -Name $scnResourceGroupName -Location $scnResourceGroupLocation

            $scnRetryCount = 0
            $scnRetryErrors = @()

            do {
                try {
                    Invoke-Command -ScriptBlock $ScenarioScript -ArgumentList $scnResourceGroupName, $scnResourceGroupLocation -ErrorAction Stop
                    break
                }
                catch {
                    if ($scnRetryCount -eq 0) {
                        $scnErrorDetails = "Error occurred when testing scenario '$Name' with error message '$($_.Exception.Message)'"
                    }
                    else {
                        $scnErrorDetails = "Error occurred when retrying #$scnRetryCount of scenario with error message '$($_.Exception.Message)'"
                    }

                    $scnInvocationInfo = $_.Exception.CommandInvocation
                    if ($null -ne $scnInvocationInfo) {
                        $scnErrorDetails += " thrown at line:$($scnInvocationInfo.ScriptLineNumber) char:$($scnInvocationInfo.OffsetInLine) by cmdlet '$($scnInvocationInfo.InvocationName)' on '$($scnInvocationInfo.Line.ToString().Trim())'."
                    }

                    $scnRetryErrors += $scnErrorDetails

                    if ($scnRetryCount -lt $script:ScenarioMaxRetryCount) {
                        $scnRetryCount++
                        $exponentialDelay = [Math]::Min((1 -shl ($scnRetryCount - 1)) * [int](Get-Random -Minimum ($script:ScenarioDelay * 0.8) -Maximum ($script:ScenarioDelay * 1.2)), $script:ScenarioMaxDelay)
                        Write-Warning "Error occurred when testing scenario '$Name'. Live test will retry automatically in $exponentialDelay seconds."
                        Start-Sleep -Seconds $exponentialDelay
                        Write-Host "Retrying #$scnRetryCount to test scenario $Name."
                    }
                    else {
                        $scnCsvData.IsSuccess = $false
                        $scnCsvData.Error = $scnRetryErrors -join ";"
                        throw "Failed to test scenario '$Name' after retrying for $script:ScenarioMaxRetryCount time(s)."
                    }
                }
            }
            while ($true)
        }
        catch {
            $scnCsvData.IsSuccess = $false
            $scnCsvData.Error += $_.Exception.Message
        }
        finally {
            Clear-LiveTestResources -Name $scnResourceGroupName
            $scnCsvData.EndDateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
            Export-Csv -LiteralPath $script:LiveTestRawCsvFile -InputObject $scnCsvData -NoTypeInformation -Append
        }
    }

    function Clear-LiveTestResources {
        [CmdletBinding()]
        [OutputType([void])]
        param (
            [Parameter(Mandatory, Position = 0)]
            [ValidateNotNullOrEmpty()]
            [Alias("ResourceGroupname")]
            [string] $Name
        )

        Invoke-LiveTestCommand -Command { Remove-AzResourceGroup -Name $Name -Force }
        #Start-Job -ScriptBlock { Remove-AzResourceGroup -Name $Name -Force }
    }

    if ($Source -eq "Local") {
        Install-LiveTestAzModules -Source $Source -RepoLocation $RepoLocation
    }
    else {
        Install-LiveTestAzModules -Source $Source
    }

    Initialize-LiveTestModule -Name $Name
}
