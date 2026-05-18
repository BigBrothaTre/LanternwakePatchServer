param(
    [string]$Config = ".\lanternwake_patch_config.json"
)

$ErrorActionPreference = "Stop"

function Write-LanternwakeLine {
    param([string]$Message)
    Write-Host "[Lanternwake Patch Packager] $Message"
}

function Convert-ToLowerHash {
    param([string]$FilePath)
    return ((Get-FileHash $FilePath -Algorithm SHA256).Hash).ToLowerInvariant()
}

function New-CleanZipFromFolder {
    param(
        [string]$SourceFolder,
        [string]$ZipPath
    )

    if (!(Test-Path $SourceFolder)) {
        throw "Source folder not found: $SourceFolder"
    }

    if (Test-Path $ZipPath) {
        Remove-Item $ZipPath -Force
    }

    $folderName = Split-Path $SourceFolder -Leaf
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("LanternwakePatch_" + [System.Guid]::NewGuid().ToString("N"))
    $tempFolder = Join-Path $tempRoot $folderName

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    try {
        Copy-Item -Path $SourceFolder -Destination $tempFolder -Recurse -Force

        # Remove common junk files from the staged copy.
        Get-ChildItem -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -in @(".git", ".github", "__MACOSX") -or
                $_.Name -like "*.bak" -or
                $_.Name -like "*.tmp" -or
                $_.Name -like "*~"
            } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        Compress-Archive -Path $tempFolder -DestinationPath $ZipPath -Force
    }
    finally {
        if (Test-Path $tempRoot) {
            Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if (!(Test-Path $Config)) {
    throw "Config file not found: $Config"
}

$configData = Get-Content $Config -Raw | ConvertFrom-Json

$patchRoot = Resolve-Path $configData.PatchRepoRoot
$patchesFolder = Join-Path $patchRoot $configData.PatchesFolder
$manifestPath = Join-Path $patchRoot $configData.ManifestFile

New-Item -ItemType Directory -Force -Path $patchesFolder | Out-Null

$manifestFiles = @()

foreach ($package in $configData.Packages) {
    Write-LanternwakeLine "Packaging $($package.Name)..."

    $sourceFolder = $package.SourceFolder
    $zipName = $package.ZipName
    $zipPath = Join-Path $patchesFolder $zipName

    New-CleanZipFromFolder -SourceFolder $sourceFolder -ZipPath $zipPath

    $hash = Convert-ToLowerHash -FilePath $zipPath
    Write-LanternwakeLine "Created $zipPath"
    Write-LanternwakeLine "SHA256 $hash"

    $manifestFiles += [ordered]@{
        name = $package.Name
        url = ($configData.BaseRawUrl.TrimEnd("/") + "/" + $configData.PatchesFolder.Trim("/") + "/" + $zipName)
        destination = $package.Destination
        type = "zip"
        sha256 = $hash
        version = $package.Version
    }
}

$manifest = [ordered]@{
    gameVersion = $configData.GameVersion
    requiredClient = $configData.RequiredClient
    realmlist = $configData.Realmlist
    files = $manifestFiles
}

$manifestJson = $manifest | ConvertTo-Json -Depth 10
Set-Content -Path $manifestPath -Value $manifestJson -Encoding UTF8

Write-LanternwakeLine "Manifest updated:"
Write-LanternwakeLine $manifestPath
Write-LanternwakeLine "Done."
