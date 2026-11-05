# Builds the web app and publishes it to Cloudflare (amuse.lexdes.com), using
# the static-assets settings in wrangler.jsonc. One-time: `npx wrangler login`.
#   powershell -File tool/deploy_web.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot)

# Bake the pubspec version into the bundle, so Settings → About shows the
# version the browser is actually running (see lib/core/app_version.dart).
$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
if (-not $version) { throw 'No version: line in pubspec.yaml' }
Write-Host "Building Amuse $version"

flutter build web --release --dart-define-from-file=config/app_config.json --dart-define=AMUSE_VERSION=$version
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

npx --yes wrangler@4 deploy
exit $LASTEXITCODE
