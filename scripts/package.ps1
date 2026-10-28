param(
    [string]$ContactEmail = ''
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$source = $workspace
$manifest = Get-Content -LiteralPath (Join-Path $source 'plugin.json') -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($ContactEmail)) { $ContactEmail = $manifest.contactEmailAddress }
$parsedAddress = [System.Net.Mail.MailAddress]::new($ContactEmail)
if ($parsedAddress.Address -ne $ContactEmail -or $ContactEmail -notmatch '\.') {
    throw 'Provide a valid public support email address.'
}
$destination = Join-Path $workspace 'dist'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$manifest | Add-Member -NotePropertyName contactEmailAddress -NotePropertyValue $ContactEmail -Force
if ($manifest.requiredDependencies.prettyui -isnot [ValueType]) {
    throw 'Package with the published numeric PrettyUI dependency, not a local development path.'
}
Add-Type -AssemblyName System.IO.Compression
$archivePath = Join-Path $destination 'boundingbox.zip'
$stream = [System.IO.File]::Open($archivePath, [System.IO.FileMode]::Create)
$archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $files = @('main.lua', 'README.md', 'LICENSE') + @(Get-ChildItem -LiteralPath (Join-Path $source 'src') -Filter '*.lua' -Recurse -File |
        ForEach-Object { [System.IO.Path]::GetRelativePath($source, $_.FullName) })
    foreach ($file in $files) {
        $entry = $archive.CreateEntry($file.Replace('\', '/'))
        $entryStream = $entry.Open()
        try {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $source $file))
            $entryStream.Write($bytes, 0, $bytes.Length)
        } finally { $entryStream.Dispose() }
    }
    $entry = $archive.CreateEntry('plugin.json')
    $writer = [System.IO.StreamWriter]::new($entry.Open(), [System.Text.UTF8Encoding]::new($false))
    try { $writer.Write(($manifest | ConvertTo-Json -Depth 10)) } finally { $writer.Dispose() }
} finally {
    $archive.Dispose()
    $stream.Dispose()
}
Write-Output $archivePath
