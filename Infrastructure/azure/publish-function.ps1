[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [Alias('rg')]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [Alias('app')]
    [string]$FunctionAppName
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue) -and -not (Test-Path '/opt/homebrew/bin/az')) {
    throw 'Azure CLI is required.'
}
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw '.NET 8 SDK is required.'
}

$az = if (Get-Command az -ErrorAction SilentlyContinue) { (Get-Command az).Source } else { '/opt/homebrew/bin/az' }
$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
$project = Join-Path $root 'Backend/QuickElevate.Api/QuickElevate.Api.csproj'
$publishDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "quickelevate-function-$([guid]::NewGuid().ToString('N'))"
$archive = "$publishDirectory.zip"

try {
    & dotnet publish $project --configuration Release --output $publishDirectory
    Compress-Archive -Path "$publishDirectory/*" -DestinationPath $archive -Force
    & $az functionapp deployment source config-zip --resource-group $ResourceGroupName --name $FunctionAppName --src $archive
}
finally {
    Remove-Item $publishDirectory, $archive -Recurse -Force -ErrorAction SilentlyContinue
}
