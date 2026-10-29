[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputJar,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedJarSha256,
    [Parameter(Mandatory)][ValidatePattern('^[0-9]{17}$')][string]$SteamID64,
    [Parameter(Mandatory)][string]$PrivateKeyFile,
    [Parameter(Mandatory)][string]$PzHome,
    [Parameter(Mandatory)][string]$JdkHome,
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$jar = (Resolve-Path -LiteralPath $InputJar).Path
$inputHash = (Get-FileHash -LiteralPath $jar).Hash
if ($inputHash -ne $ExpectedJarSha256) { throw 'Input JAR differs from the selected build/candidate hash' }
$key = (Resolve-Path -LiteralPath $PrivateKeyFile).Path
if ($SteamID64 -ne '76561199098893636') { throw 'Signer differs from the verified uploader of Knox Survivors Workshop item 3749727604; reconcile author identity first' }
if (!(Test-Path -LiteralPath $key -PathType Leaf)) { throw 'Private key must be a file' }
if ($key.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Signing key must be outside repository' }
if ($key.StartsWith((Join-Path $env:USERPROFILE 'Zomboid') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Signing key must be outside game data and mod directories' }
$gameRoot = (Resolve-Path -LiteralPath $PzHome).Path.TrimEnd('\', '/')
if ($key.StartsWith($gameRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Signing key must be outside the configured game installation' }
if ((Get-Item -LiteralPath $key).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Private key must not be a symbolic link' }
for ($cursor = (Get-Item -LiteralPath $key).Directory; $null -ne $cursor; $cursor = $cursor.Parent) {
    if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Signing key path must not contain a junction or symbolic link' }
}
if (!$OutputDirectory) { $OutputDirectory = Join-Path $root ('build/zbs/' + [Guid]::NewGuid().ToString('N')) }
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$allowed = [IO.Path]::GetFullPath((Join-Path $root 'build/zbs')) + '\'
if (!$outputRoot.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Signing output must be under build/zbs, never protected candidates or installations' }
if (Test-Path -LiteralPath $outputRoot) { throw 'Signing output already exists; choose a fresh directory' }
for ($cursor = [IO.DirectoryInfo]$outputRoot; $null -ne $cursor; $cursor = $cursor.Parent) {
    if ($cursor.Exists -and ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Signing output path must not contain a junction or symbolic link' }
}
$framework = Join-Path $PzHome 'ZombieBuddy.jar'
$java = Join-Path $PzHome 'jre64/bin/java.exe'
$javac = Join-Path $JdkHome 'bin/javac.exe'
foreach ($file in @($framework, $java, $javac)) { if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw 'Required installed Java/signing tool unavailable' } }
$classes = Join-Path $root 'build/zbs-tool/classes'
New-Item -ItemType Directory -Path $classes -Force | Out-Null
& $javac '--release' '17' '-cp' $framework '-d' $classes (Join-Path $PSScriptRoot 'zbs/ZbsTool.java')
if ($LASTEXITCODE -ne 0) { throw 'Signing tool compilation failed' }
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$target = Join-Path $outputRoot 'knox-survivors.jar'
Copy-Item -LiteralPath $jar -Destination $target
(Get-Item -LiteralPath $target).IsReadOnly = $false
$hash = $ExpectedJarSha256
if ((Get-FileHash -LiteralPath $target).Hash -ne $hash) { throw 'JAR copy mismatch' }
& $java "-Duser.home=$(Join-Path $root 'build/zbs-tool/isolated-home')" '-cp' "$classes;$framework" 'ZbsTool' 'sign' $target $SteamID64 $key
if ($LASTEXITCODE -ne 0) { throw 'ZBS signing/verification failed; output must not be packaged' }
if ((Get-FileHash -LiteralPath $target).Hash -ne $hash -or (Get-FileHash -LiteralPath $jar).Hash -ne $hash) { throw 'Final JAR changed' }
Write-Output "Signed JAR prepared under $outputRoot; no installation or public-key publication performed."
