param (
    [Parameter(Mandatory)]
    [ValidateSet("PSGallery", "LocalRepo", IgnoreCase = $false)]
    [string] $Source,

    [Parameter()]
    [string] $RepoLocation
)

switch ($Source) {
    "PSGallery" {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Install-Module -Name Az -Repository PSGallery -Scope CurrentUser -AllowClobber -Force
    }
    "LocalRepo" {
        Register-PSRepository -Name LocalGallery -SourceLocation $RepoLocation -PackageManagementProvider NuGet -InstallationPolicy Trusted
        Install-Module -Name Az -Repository LocalGallery -Scope CurrentUser -AllowClobber -Force
    }
}

Import-Module -Name Az -Force
