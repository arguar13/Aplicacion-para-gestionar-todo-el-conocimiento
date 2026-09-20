<#
.SYNOPSIS
  Corre el benchmark de Sinapsis en un Android real y guarda las cifras en
  docs/benchmarks/<dispositivo>/<fecha>/.

.DESCRIPTION
  Mide en modo profile (`flutter drive --profile`), que es el código de la app
  de verdad: en debug las cifras del Dart serían de 5 a 10 veces peores.

  Usa el flavor `staging` (app.sinapsis.staging) para no tocar los datos de
  ninguna otra instalación de Sinapsis del teléfono: cada flavor es otra app
  para Android, con sus datos propios. El benchmark además nunca abre la base
  de la app: trabaja con copias en su directorio temporal.

  Prerrequisitos: un teléfono con depuración USB, con el cable conectado, la
  pantalla desbloqueada y cargando, y al menos -MinFreeGB libres. Para la
  migración y la fusión a escala hacen falta las bóvedas grandes: -PushVaults
  las copia con `adb push`.

.EXAMPLE
  tool/bench_android.ps1                       # el benchmark de los 13 escenarios
  tool/bench_android.ps1 -PushVaults           # antes, empuja las bóvedas
  tool/bench_android.ps1 -Target vault_merge_benchmark_test
  tool/bench_android.ps1 -DryRun               # solo muestra qué haría
#>
[CmdletBinding()]
param(
  # El número de serie de adb. Si hay un solo dispositivo, se usa ese.
  [string] $Device,
  [string] $Flavor = 'staging',
  # El archivo de integration_test/ sin la extensión.
  [string] $Target = 'vault_benchmark_test',
  [string] $OutRoot = 'docs/benchmarks',
  [int] $MinFreeGB = 4,
  [switch] $PushVaults,
  [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

function Find-Adb {
  $fromPath = Get-Command adb -ErrorAction SilentlyContinue
  if ($fromPath) { return $fromPath.Source }
  foreach ($root in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)) {
    if ($root) {
      $candidate = Join-Path $root 'platform-tools/adb.exe'
      if (Test-Path $candidate) { return $candidate }
    }
  }
  throw 'No encuentro adb: agregá platform-tools al PATH o definí ANDROID_HOME.'
}

$adb = Find-Adb

# --- Qué dispositivo -------------------------------------------------------
$listed = & $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\S' }
$ready = @($listed | Where-Object { $_ -match '\sdevice$' } | ForEach-Object { ($_ -split '\s+')[0] })
$blocked = @($listed | Where-Object { $_ -notmatch '\sdevice$' })

if ($blocked.Count -gt 0) {
  Write-Warning ("Dispositivos que adb ve pero no puede usar: " + ($blocked -join '; ') +
    ". Autorizá la depuración USB en el teléfono.")
}
if ($ready.Count -eq 0) {
  throw 'No hay ningún Android conectado y autorizado (adb devices está vacío). Conectá el teléfono por USB con la depuración activada.'
}
if (-not $Device) {
  if ($ready.Count -gt 1) {
    throw ("Hay varios dispositivos (" + ($ready -join ', ') + "): elegí uno con -Device.")
  }
  $Device = $ready[0]
} elseif ($ready -notcontains $Device) {
  throw "El dispositivo '$Device' no está entre los listos: $($ready -join ', ')"
}

function Get-Prop([string] $name) {
  (& $adb -s $Device shell getprop $name).Trim()
}

# --- Qué es, para que las cifras digan de qué máquina son --------------------
$manufacturer = Get-Prop 'ro.product.manufacturer'
$model = Get-Prop 'ro.product.model'
$release = Get-Prop 'ro.build.version.release'
$sdk = Get-Prop 'ro.build.version.sdk'
$soc = (Get-Prop 'ro.soc.model')
if (-not $soc) { $soc = Get-Prop 'ro.hardware' }
$memKb = [int64]((& $adb -s $Device shell 'grep MemTotal /proc/meminfo') -replace '[^0-9]', '')
$memGb = [math]::Round($memKb / 1MB, 1)
$dfLine = (& $adb -s $Device shell 'df -k /data' | Select-Object -Last 1) -split '\s+'
$freeGb = [math]::Round([int64]$dfLine[3] / 1MB, 1)
$battery = (& $adb -s $Device shell 'dumpsys battery') -join ' '
$temperature = if ($battery -match 'temperature: (\d+)') { [int]$Matches[1] / 10 } else { $null }
$charging = $battery -match 'status: 2'

$info = "$manufacturer $model, Android $release (API $sdk), $soc, $memGb GB de RAM"
Write-Host "Dispositivo: $info"
Write-Host "Libre en /data: $freeGb GB; batería: $temperature °C, cargando: $charging"

if ($freeGb -lt $MinFreeGB) {
  throw "Hay $freeGb GB libres y hacen falta al menos $MinFreeGB GB (las bóvedas de 10.000 elementos pesan cientos de MB y la fusión y la migración las copian)."
}
if (-not $charging) {
  Write-Warning 'El teléfono no está cargando: el ahorro de energía puede bajar la frecuencia del procesador y falsear las cifras.'
}
if ($temperature -and $temperature -gt 38) {
  Write-Warning "El teléfono está a $temperature °C: esperá a que se enfríe, el calor también baja la frecuencia."
}

# --- Adónde van las cifras ---------------------------------------------------
$tag = ("$manufacturer-$model-android$release" -replace '[^A-Za-z0-9._-]', '_')
$out = Join-Path $OutRoot "$tag/$(Get-Date -Format 'yyyy-MM-dd')"
$package = "app.sinapsis.$Flavor"
$bench = "/sdcard/Android/data/$package/files/bench"

$defines = Join-Path ([System.IO.Path]::GetTempPath()) 'sinapsis-bench-defines.json'
@{ BENCH_DEVICE_INFO = $info } | ConvertTo-Json | Set-Content -Path $defines -Encoding utf8

$flutterArgs = @(
  'drive', '--profile', '--flavor', $Flavor, '-d', $Device,
  '--driver=test_driver/integration_test.dart',
  "--target=integration_test/$Target.dart",
  "--dart-define-from-file=$defines"
)

# --- Empujar las bóvedas grandes --------------------------------------------
if ($PushVaults) {
  $source = '.dart_tool/sinapsis_benchmark'
  $files = @(
    'vault_s17_g4_10000.sqlite',     # esquema v17: la migración
    'vault_s20_g4_10000.sqlite'      # la actual: la fusión y los 13 escenarios
  ) | Where-Object { Test-Path (Join-Path $source $_) }
  if ($files.Count -eq 0) {
    Write-Warning "No hay bóvedas en ${source}: corré el benchmark de escritorio una vez para armarlas."
  }
  foreach ($file in $files) {
    $command = "adb -s $Device push $(Join-Path $source $file) $bench/$file"
    if ($DryRun) { Write-Host "[dry-run] $command" } else {
      & $adb -s $Device shell "mkdir -p $bench"
      & $adb -s $Device push (Join-Path $source $file) "$bench/$file"
    }
  }
}

Write-Host "Cifras a: $out"
Write-Host "flutter $($flutterArgs -join ' ')"
if ($DryRun) { return }

New-Item -ItemType Directory -Force -Path $out | Out-Null
$env:BENCH_OUT = (Resolve-Path $out).Path
& flutter @flutterArgs
if ($LASTEXITCODE -ne 0) {
  Write-Warning "flutter drive terminó con ${LASTEXITCODE}: si es por un umbral, el informe se guardó igual y muestra qué escenario no cumplió."
}

# Deja constancia del dispositivo junto a las cifras.
@(
  "# Dispositivo",
  "",
  "- Modelo: $manufacturer $model",
  "- Android: $release (API $sdk)",
  "- SoC: $soc",
  "- RAM: $memGb GB",
  "- Libre en /data al empezar: $freeGb GB",
  "- Temperatura de la batería al empezar: $temperature °C (cargando: $charging)",
  "- Flavor: $Flavor ($package), modo profile",
  "- Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
) | Set-Content -Path (Join-Path $out 'dispositivo.md') -Encoding utf8
