<#
.SYNOPSIS
  Corre el benchmark de Sinapsis en un Android —un teléfono real o un
  emulador— y guarda las cifras en docs/benchmarks/<dispositivo>/<fecha>/.

.DESCRIPTION
  Mide en modo profile (`flutter drive --profile`), que es el código de la app
  de verdad: en debug las cifras del Dart serían de 5 a 10 veces peores.

  Usa el flavor `staging` (app.sinapsis.staging) para no tocar los datos de
  ninguna otra instalación de Sinapsis del teléfono: cada flavor es otra app
  para Android, con sus datos propios. El benchmark además nunca abre la base
  de la app: trabaja con copias en su directorio temporal.

  Prerrequisitos: un teléfono con depuración USB, con el cable conectado, la
  pantalla desbloqueada y cargando —o un emulador arrancado—, y al menos
  -MinFreeGB libres. Para la migración y la fusión a escala hacen falta las
  bóvedas grandes: -PushVaults las copia con `adb push`.

  UN EMULADOR SE RECONOCE Y SE ROTULA («emulador-…» en la carpeta y en
  dispositivo.md): usa la CPU y el disco de la máquina donde corre, así que sus
  TIEMPOS son optimistas y no valen como los de un teléfono de gama media. Lo
  que sí vale es la MEMORIA —el sistema mata la app en cuanto se pasa del
  límite del emulador—, y que el arnés y el código corren en Android.

.EXAMPLE
  tool/bench_android.ps1                       # el benchmark de los 13 escenarios
  tool/bench_android.ps1 -PushVaults           # antes, empuja las bóvedas
  tool/bench_android.ps1 -Target vault_merge_benchmark_test
  tool/bench_android.ps1 -Target vault_backup_benchmark_test -SaveToFolder   # + tool/bench_android_pick_folder.ps1
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
  # Para `vault_backup_benchmark_test`: además de armar la copia, la guarda en
  # una carpeta elegida con el selector del sistema. Alguien tiene que manejar
  # ese selector: `tool/bench_android_pick_folder.ps1`, en otra terminal.
  [switch] $SaveToFolder,
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

# Un emulador usa la CPU y el disco del anfitrión: se rotula para que sus cifras
# no se lean como las de un teléfono.
$isEmulator = ((Get-Prop 'ro.kernel.qemu') -eq '1') -or ((Get-Prop 'ro.boot.qemu') -eq '1') -or
  ($model -match 'sdk_gphone|Android SDK|Emulator')
$kind = if ($isEmulator) { 'EMULADOR' } else { 'teléfono' }

# Un emulador corre sobre la PC: con la PC a batería el sistema le baja la
# frecuencia al procesador y al disco, y la misma medición sale de 3 a 5 veces
# peor (armar la copia: 45 s enchufada, 227 s a batería). Se avisa y se anota.
$hostOnBattery = $false
if ($isEmulator) {
  $hostBattery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
  $hostOnBattery = [bool]($hostBattery -and $hostBattery.BatteryStatus -eq 1)
}
$info = "$kind $manufacturer $model, Android $release (API $sdk), $soc, $memGb GB de RAM"
Write-Host "Dispositivo: $info"
Write-Host "Libre en /data: $freeGb GB; batería: $temperature °C, cargando: $charging"

if ($freeGb -lt $MinFreeGB) {
  throw "Hay $freeGb GB libres y hacen falta al menos $MinFreeGB GB (las bóvedas de 10.000 elementos pesan cientos de MB y la fusión y la migración las copian)."
}
if ($isEmulator) {
  Write-Warning 'Es un EMULADOR: los tiempos son de la máquina anfitriona (optimistas); las cifras de memoria sí valen.'
  if ($hostOnBattery) {
    Write-Warning 'La PC que aloja el emulador funciona a BATERÍA: los tiempos saldrán de 3 a 5 veces peores. Enchufala y repetí.'
  }
} elseif (-not $charging) {
  Write-Warning 'El teléfono no está cargando: el ahorro de energía puede bajar la frecuencia del procesador y falsear las cifras.'
}
if (-not $isEmulator -and $temperature -and $temperature -gt 38) {
  Write-Warning "El teléfono está a $temperature °C: esperá a que se enfríe, el calor también baja la frecuencia."
}

# --- Adónde van las cifras ---------------------------------------------------
$tagPrefix = if ($isEmulator) { 'emulador-' } else { '' }
$tag = ("$tagPrefix$manufacturer-$model-android$release" -replace '[^A-Za-z0-9._-]', '_')
$out = Join-Path $OutRoot "$tag/$(Get-Date -Format 'yyyy-MM-dd')"
$package = "app.sinapsis.$Flavor"
$bench = "/sdcard/Android/data/$package/files/bench"

$defines = Join-Path ([System.IO.Path]::GetTempPath()) 'sinapsis-bench-defines.json'
$defineValues = @{ BENCH_DEVICE_INFO = $info }
if ($SaveToFolder) { $defineValues['BENCH_SAVE_TO_FOLDER'] = 'true' }
$defineValues | ConvertTo-Json | Set-Content -Path $defines -Encoding utf8

# `--no-dds`: sin él, `watchPerformance` —que se conecta al servicio de la VM
# desde DENTRO de la app— usa un puerto del anfitrión que en el dispositivo no
# existe, y la medición de cuadros falla con «Connection refused».
$flutterArgs = @(
  'drive', '--profile', '--no-dds', '--flavor', $Flavor, '-d', $Device,
  '--driver=test_driver/integration_test.dart',
  "--target=integration_test/$Target.dart",
  "--dart-define-from-file=$defines"
)

# Solo la ABI del dispositivo: `flutter drive` compilaría las tres (arm, arm64 y
# x64), que tarda el triple y no sirve de nada. Se arma el APK del blanco pedido
# para esa ABI y `drive` lo usa tal cual —por eso los `--dart-define` van también
# acá: con un APK ya armado, `drive` no los aplica—.
$abi = Get-Prop 'ro.product.cpu.abi'
$platform = switch ($abi) {
  'arm64-v8a' { 'android-arm64' }
  'armeabi-v7a' { 'android-arm' }
  'x86_64' { 'android-x64' }
  default { $null }
}
if ($platform) {
  $apk = "build/app/outputs/flutter-apk/app-$Flavor-profile.apk"
  $buildArgs = @(
    'build', 'apk', '--profile', '--flavor', $Flavor,
    '--target-platform', $platform, '-t', "integration_test/$Target.dart",
    "--dart-define-from-file=$defines"
  )
  Write-Host "flutter $($buildArgs -join ' ')"
  if (-not $DryRun) {
    # flutter avisa por stderr (la versión de AGP, por ejemplo): con 'Stop',
    # PowerShell 5.1 lo toma por un error y corta el guion.
    $ErrorActionPreference = 'Continue'
    & flutter @buildArgs
    $buildExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($buildExit -ne 0) { throw "flutter build apk terminó con $buildExit" }
  }
  $flutterArgs += "--use-application-binary=$apk"
}

# --- Empujar las bóvedas grandes --------------------------------------------
if ($PushVaults) {
  # `flutter drive` desinstala la app al terminar y con ella se va lo empujado:
  # hay que empujar antes de CADA corrida. Y lo que `adb` deja en la carpeta de
  # la app queda a nombre de `shell` con permiso 660 (dueño y grupo
  # `ext_data_rw`, del que la app no es parte): sin abrirle los permisos la app
  # ve la carpeta pero no puede abrir ningún archivo —«Permission denied»— y
  # cada escenario arma su bóveda de cero, o se salta.
  $source = '.dart_tool/sinapsis_benchmark'
  # La marca `.ok` va al final: sin ella la bóveda no cuenta por completa.
  $files = @(
    'vault_s17_g4_10000.sqlite',     # esquema v17: la migración
    'vault_s20_g4_10000.sqlite',     # la actual: la fusión y los 13 escenarios...
    'vault_s20_g4_10000.json',       # ...con su resumen
    'vault_s20_g4_10000.ok'          # ...y su marca de completa
  ) | Where-Object { Test-Path (Join-Path $source $_) }
  if ($files.Count -eq 0) {
    Write-Warning "No hay bóvedas en ${source}: corré el benchmark de escritorio una vez para armarlas."
  }
  foreach ($file in $files) {
    $command = "adb -s $Device push $(Join-Path $source $file) $bench/$file"
    if ($DryRun) { Write-Host "[dry-run] $command" } else {
      & $adb -s $Device shell "mkdir -p $bench"
      # `adb push` cuenta lo que hizo por stderr: con 'Stop', PowerShell 5.1 lo
      # toma por un error y corta el guion aunque la copia haya salido bien.
      $ErrorActionPreference = 'Continue'
      & $adb -s $Device push (Join-Path $source $file) "$bench/$file"
      $pushExit = $LASTEXITCODE
      $ErrorActionPreference = 'Stop'
      if ($pushExit -ne 0) { throw "adb push de $file terminó con $pushExit" }
      & $adb -s $Device shell "chmod 777 $bench; chmod 666 $bench/$file"
    }
  }
}

Write-Host "Cifras a: $out"
Write-Host "flutter $($flutterArgs -join ' ')"
if ($DryRun) { return }

New-Item -ItemType Directory -Force -Path $out | Out-Null
$env:BENCH_OUT = (Resolve-Path $out).Path
$ErrorActionPreference = 'Continue'
& flutter @flutterArgs
$driveExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($driveExit -ne 0) {
  Write-Warning "flutter drive terminó con ${driveExit}: si es por un umbral, el informe se guardó igual y muestra qué escenario no cumplió."
}

# Deja constancia del dispositivo junto a las cifras.
@(
  "# Dispositivo",
  "",
  "- Tipo: $kind$(if ($isEmulator) { ' (los tiempos son de la máquina anfitriona; las cifras de memoria sí valen)' })",
  "- Modelo: $manufacturer $model",
  "- Android: $release (API $sdk)",
  "- SoC: $soc",
  "- RAM: $memGb GB",
  "- Libre en /data al empezar: $freeGb GB",
  $(if ($isEmulator) { "- PC anfitriona: $(if ($hostOnBattery) { 'a BATERÍA (los tiempos salen de 3 a 5 veces peores)' } else { 'enchufada' })" }),
  "- Temperatura de la batería al empezar: $temperature °C (cargando: $charging)",
  "- Flavor: $Flavor ($package), modo profile",
  "- Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
) | Set-Content -Path (Join-Path $out 'dispositivo.md') -Encoding utf8
