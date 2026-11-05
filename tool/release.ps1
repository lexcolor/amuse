# Builds the release artefacts for the version in pubspec.yaml:
#   build/installer/amuse-<version>-windows-setup.exe   (needs Inno Setup 6)
#   build/installer/amuse-<version>-android.apk         (needs android/key.properties)
# then tags the commit and uploads both to a GitHub release (needs `gh auth login`).
#   powershell -File tool/release.ps1            # build only
#   powershell -File tool/release.ps1 -Publish   # build, tag v<version>, create the release
param([switch]$Publish)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot)

$full = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$version = $full.Split('+')[0]
$out = 'build\installer'
New-Item -ItemType Directory -Force $out | Out-Null
Write-Host "Building Amuse $full"

flutter build windows --release --dart-define-from-file=config/app_config.json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$iscc = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) { $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
& $iscc /Q "/DAppVersion=$version" tool\windows\installer.iss
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not (Test-Path android\key.properties)) { throw 'android\key.properties is missing: release APKs must be signed with the upload key' }
flutter build apk --release --dart-define-from-file=config/app_config.json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-Item build\app\outputs\flutter-apk\app-release.apk "$out\amuse-$version-android.apk" -Force

$setup = "$out\amuse-$version-windows-setup.exe"
$apk = "$out\amuse-$version-android.apk"
Get-Item $setup, $apk | Select-Object Name, Length

if ($Publish) {
  $tag = "v$version"
  if (-not (git tag --list $tag)) { git tag -a $tag -m "Amuse $version" }
  git push origin $tag
  gh release create $tag $setup $apk --title "Amuse $version" --generate-notes
}
