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

New-Variable -Name RepoRootDirectory -Value ($PSScriptRoot | Split-Path | Split-Path | Split-Path) -Scope Script -Option Constant
New-Variable -Name ArtifactsDirectory -Value (Join-Path -Path $script:RepoRootDirectory -ChildPath "artifacts") -Scope Script -Option Constant
New-Variable -Name LiveTestRootDirectory -Value (Join-Path -Path $script:ArtifactsDirectory -ChildPath "LiveTestAnalysis") -Scope Script -Option Constant
New-Variable -Name LiveTestRawDirectory -Value (Join-Path -Path $script:LiveTestRootDirectory -ChildPath "Raw") -Scope Script -Option Constant

function Initialize-KustoPackage {
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    $packageProviderName = "NuGet"
    $kustoPackageName = "microsoft.azure.kusto.ingest"
    $kustoPackageVersion = "11.1.0"
    $kustoPackage = Find-Package -ProviderName $packageProviderName -Name $kustoPackageName -RequiredVersion $kustoPackageVersion -ErrorAction SilentlyContinue

    if ($null -eq $kustoPackage) {
        Install-Package -ProviderName $packageProviderName -Name $kustoPackageName -RequiredVersion $kustoPackageVersion -Scope CurrentUser -Force
    }

    $kustoPackages = @(
        @{ PackageName = "azure.core"; PackageVersion = "1.22.0"; DllName = "Azure.Core.dll" },
        @{ PackageName = "azure.data.tables"; PackageVersion = "12.5.0"; DllName = "Azure.Data.Tables.dll" },
        @{ PackageName = "azure.storage.blobs"; PackageVersion = "12.10.0"; DllName = "Azure.Storage.Blobs.dll" },
        @{ PackageName = "azure.storage.common"; PackageVersion = "12.9.0"; DllName = "Azure.Storage.Common.dll" },
        @{ PackageName = "azure.storage.queues"; PackageVersion = "12.8.0"; DllName = "Azure.Storage.Queues.dll" },
        @{ PackageName = "microsoft.azure.kusto.cloud.platform"; PackageVersion = "11.1.0"; DllName = "Kusto.Cloud.Platform.dll" },
        @{ PackageName = "microsoft.azure.kusto.cloud.platform.aad"; PackageVersion = "11.1.0"; DllName = "Kusto.Cloud.Platform.Aad.dll" },
        @{ PackageName = "microsoft.azure.kusto.data"; PackageVersion = "11.1.0"; DllName = "Kusto.Data.dll" },
        @{ PackageName = "microsoft.azure.kusto.ingest"; PackageVersion = "11.1.0"; DllName = "Kusto.Ingest.dll" },
        @{ PackageName = "microsoft.identity.client"; PackageVersion = "4.46.0"; DllName = "Microsoft.Identity.Client.dll" },
        @{ PackageName = "microsoft.identitymodel.abstractions"; PackageVersion = "6.18.0"; DllName = "Microsoft.IdentityModel.Abstractions.dll" },
        @{ PackageName = "microsoft.io.recyclablememorystream"; PackageVersion = "2.2.0"; DllName = "Microsoft.IO.RecyclableMemoryStream.dll" },
        @{ PackageName = "system.memory.data"; PackageVersion = "1.0.2"; DllName = "System.Memory.Data.dll" }
    )

    $kustoPackages | ForEach-Object {
        Add-Type -LiteralPath "$($env:USERPROFILE)\.nuget\packages\$($_['PackageName'])\$($_['PackageVersion'])\lib\netstandard2.0\$($_['DllName'])"
    }
}

function Import-KustoDataFromCsv {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [guid] $TenantId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ClusterName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ClusterRegion,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $DatabaseName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TableName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [guid] $ServicePrincipalId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ServicePrincipalSecret
    )

    $ingestUri = "https://ingest-$ClusterName.$ClusterRegion.kusto.windows.net"
    $ingestBuilder = [Kusto.Data.KustoConnectionStringBuilder]::new($ingestUri).WithAadApplicationKeyAuthentication($ServicePrincipalId, $ServicePrincipalSecret, $TenantId.ToString())
    IngestDataFromCsv -IngestBuilder $ingestBuilder -DatabaseName $DatabaseName -TableName $TableName
}

function IngestDataFromCsv {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $IngestBuilder,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $DatabaseName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TableName
    )

    try {
        $ingestClient = [Kusto.Ingest.KustoIngestFactory]::CreateQueuedIngestClient($IngestBuilder)
        $ingestionProps = [Kusto.Ingest.KustoQueuedIngestionProperties]::new($DatabaseName, $TableName)
        $ingestionProps.Format = [Kusto.Data.Common.DataSourceFormat]::csv
        $ingestionProps.IgnoreFirstRecord = $true

        $ingestionMapping = [Kusto.Ingest.IngestionMapping]::new()
        $ingestionMapping.IngestionMappingKind = [Kusto.Data.Ingestion.IngestionMappingKind]::Csv
        $ingestionMapping.IngestionMappingReference = "$($TableName)_csv_mapping"

        $ingestionProps.IngestionMapping = $ingestionMapping

        Get-ChildItem -LiteralPath $script:LiveTestRawDirectory -Filter *.csv -File | ForEach-Object {
            Write-Host "Starting to import file $($_.FullName)..." -ForegroundColor Green
            $ingestClient.IngestFromStorageAsync($_.FullName, $ingestionProps).GetAwaiter().GetResult()
            Write-Host "Finished importing file $($_.FullName)." -ForegroundColor Green
        }
    }
    catch {
        throw $_
    }
    finally {
        if ($null -ne $ingestClient) {
            $ingestClient.Dispose()
        }
    }
}

Initialize-KustoPackage
