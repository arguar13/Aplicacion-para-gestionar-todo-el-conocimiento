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
  La línea base de avisos del analizador; no puede crecer. Hoy, 21 (F25, F26 y F27
  corrigieron diez).

.PARAMETER Keep
  Deja la carpeta exportada, por si hay que mirar qué falló.
#>
[CmdletBinding()]
param(
  [string] $Rev = 'HEAD',
  [int] $Baseline = 21,
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
# Tiene que corresponder al COMMIT, no a la carpeta de trabajo: copiar lo que
# hay generado ahora verificaba un commit viejo contra textos o entidades de
# otro momento —así "fallaron" tres commits sanos cuando, después, se borraron
# 15 textos de los .arb—.
#
# - Los textos traducidos se generan desde los .arb del commit: es rápido.
# - El código de build_runner (drift, freezed, json) se copia si el commit no
#   cambió ninguno de los archivos de los que sale; si cambió alguno, se
#   regenera en la exportación, que tarda unos minutos más.
New-Item -ItemType Directory -Force -Path (Join-Path $work '.dart_tool') | Out-Null
Copy-Item '.dart_tool/package_config.json' (Join-Path $work '.dart_tool/package_config.json')

$changed = @(git diff --name-only $Rev -- 'lib/*.dart' 'test/*.dart') +
  @(git ls-files --others --exclude-standard -- 'lib/*.dart' 'test/*.dart')
$generatorPart = "part '.*\.(g|freezed)\.dart'"

# Si [path] es de los que generan código, en la carpeta de trabajo o en el
# commit. Lo que no existe en uno de los dos lados no se le pregunta a ese
# lado: en PowerShell 5.1, el aviso de git por un archivo ausente corta el
# guion entero.
function Test-GeneratorInput([string] $path) {
  if ($path -like 'lib/core/database/*') { return $true }
  if ((Test-Path $path) -and (Select-String -Path $path -Pattern $generatorPart -Quiet)) {
    return $true
  }
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & git cat-file -e "${Rev}:$path" 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    return [bool]((& git show "${Rev}:$path") -match $generatorPart)
  } finally {
    $ErrorActionPreference = $previous
  }
}
$builderInputs = @($changed | Where-Object { Test-GeneratorInput $_ })

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
Push-Location $work
try {
  & flutter gen-l10n *> $null
  if ($LASTEXITCODE -ne 0) { throw "flutter gen-l10n falló en el commit $sha." }
} finally {
  Pop-Location
  $ErrorActionPreference = $previousPreference
}

if ($builderInputs.Count -eq 0) {
  # Solo de las carpetas de código del proyecto, que son las que mira
  # build_runner: sin acotar, `git ls-files` también entra a las copias de
  # trabajo de los agentes en `.claude/worktrees/` y copiaría su código
  # generado —de otro commit— o fallaría si una se borra mientras corre.
  $sourceRoots = 'lib', 'test', 'integration_test', 'tool', 'bin'
  $generatedSpecs = foreach ($root in $sourceRoots) {
    ":(glob)$root/**/*.freezed.dart"
    ":(glob)$root/**/*.g.dart"
  }
  $generated = @(git ls-files --others --ignored --exclude-standard -- @generatedSpecs)
  foreach ($file in $generated) {
    $destination = Join-Path $work $file
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item $file $destination
  }
  Write-Host "Exportado a $work (textos generados del commit; $($generated.Count) archivos de build_runner copiados)."
} else {
  Write-Host "El commit cambió $($builderInputs.Count) archivos de los que sale código generado: se regenera."
  $ErrorActionPreference = 'Continue'
  Push-Location $work
  try {
    & dart run build_runner build --delete-conflicting-outputs *> $null
    if ($LASTEXITCODE -ne 0) { throw "build_runner falló en el commit $sha." }
  } finally {
    Pop-Location
    $ErrorActionPreference = $previousPreference
  }
  Write-Host "Exportado a $work (todo lo generado, desde el commit)."
}

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
