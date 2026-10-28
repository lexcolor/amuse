# Builds the web app and publishes it to Cloudflare (amuse.lexdes.com), using
# the static-assets settings in wrangler.jsonc. One-time: `npx wrangler login`.
#   powershell -File tool/deploy_web.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot)

flutter build web --release --dart-define-from-file=config/app_config.json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

npx --yes wrangler@4 deploy
exit $LASTEXITCODE
