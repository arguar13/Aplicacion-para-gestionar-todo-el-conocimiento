<#
.SYNOPSIS
  Comprueba que un commit compila y pasa el analizador POR SÍ SOLO, sin lo que
  haya en el árbol de trabajo.

.DESCRIPTION
  El ritual de cada commit formatea, analiza y prueba el árbol de trabajo. Eso
  no prueba el commit: si un archivo nuevo quedó sin agregar, o uno borrado
  sigue referenciado, el árbol entero anda y el commit no compila. Así salió
  `2fa6ae6` (F9), que solo funcionaba con el commit siguiente.

  Este guion exporta el commit con `git archive` a una carpeta temporal, le
  suma solo los archivos GENERADOS que no se versionan (freezed, g.dart y
  localizaciones) y corre `flutter analyze` ahí. Falla si hay un error o si
  los avisos superan la línea base. También avisa si el árbol de trabajo no
  quedó limpio: tras el commit no debería haber nada modificado.

  Se corre después de CADA commit, antes del push:

      tool/verify_commit.ps1

.PARAMETER Rev
  El commit a comprobar. Por defecto, HEAD.

.PARAMETER Baseline
  La línea base de avisos del analizador; no puede crecer. Hoy, 31.

.PARAMETER Keep
  Deja la carpeta exportada, por si hay que mirar qué falló.
#>
[CmdletBinding()]
param(
  [string] $Rev = 'HEAD',
  [int] $Baseline = 31,
  [switch] $Keep
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$sha = (git rev-parse --short $Rev).Trim()
Write-Host "Comprobando el commit $sha..."

# --- El árbol de trabajo -----------------------------------------------------
$modified = @(git status --porcelain --untracked-files=no)
if ($modified.Count -gt 0) {
  Write-Warning ("El árbol de trabajo tiene cambios sin comitear (lo que se comprueba es el commit, no esto):`n" +
    ($modified -join "`n"))
}
$untracked = @(git ls-files --others --exclude-standard)
if ($untracked.Count -gt 0) {
  Write-Warning ("Hay archivos sin versionar; si el código los usa, el commit no compila:`n" +
    ($untracked -join "`n"))
}

# --- Exportar el commit -------------------------------------------------------
$work = Join-Path ([System.IO.Path]::GetTempPath()) "sinapsis-verify-$sha"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Path $work | Out-Null
$tar = Join-Path (Split-Path $work) "sinapsis-verify-$sha.tar"

$paths = @(
  'lib', 'test', 'integration_test', 'test_driver', 'tool', 'drift_schemas',
  'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'l10n.yaml'
) | Where-Object { git ls-tree --name-only $Rev -- $_ }
git archive --format=tar --output=$tar $Rev -- @paths
if ($LASTEXITCODE -ne 0) { throw 'git archive falló.' }
tar -xf $tar -C $work
Remove-Item $tar

# --- Lo generado, que no se versiona ---------------------------------------------
# Solo lo que sale de un generador: los fuentes vienen del commit.
$generated = @(git ls-files --others --ignored --exclude-standard -- '*.freezed.dart' '*.g.dart' 'lib/l10n/generated/*')
foreach ($file in $generated) {
  $destination = Join-Path $work $file
  New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
  Copy-Item $file $destination
}
New-Item -ItemType Directory -Force -Path (Join-Path $work '.dart_tool') | Out-Null
Copy-Item '.dart_tool/package_config.json' (Join-Path $work '.dart_tool/package_config.json')
Write-Host "Exportado a $work ($($generated.Count) archivos generados agregados)."

# --- Analizar ------------------------------------------------------------------
# `flutter analyze` sale con código distinto de cero y escribe su resumen por el
# error estándar cuando hay avisos: no es un fallo de este guion.
$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
Push-Location $work
try {
  $output = & flutter analyze 2>&1 | ForEach-Object { "$_" }
} finally {
  Pop-Location
  $ErrorActionPreference = $previous
}
$output | Select-Object -Last 25 | ForEach-Object { Write-Host $_ }

$errors = @($output | Where-Object { $_ -match '^\s*error\s' })
$summary = $output | Where-Object { $_ -match '(\d+) issues? found|No issues found' } | Select-Object -Last 1
$issues = if ($summary -match '(\d+) issues? found') { [int]$Matches[1] } else { 0 }

if (-not $Keep) { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }

if ($errors.Count -gt 0) {
  throw "El commit $sha NO compila por sí solo: $($errors.Count) errores. Falta un archivo en el commit, o uno borrado sigue referenciado."
}
if ($issues -gt $Baseline) {
  throw "El commit $sha tiene $issues avisos del analizador y la línea base es $Baseline."
}
Write-Host "OK: el commit $sha compila y pasa el analizador por sí solo ($issues avisos, línea base $Baseline)."
exit 0
