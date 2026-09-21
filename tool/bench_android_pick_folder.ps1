<#
.SYNOPSIS
  Maneja el selector de carpetas de Android mientras corre el benchmark de la
  copia con `-SaveToFolder`: elige una carpeta y confirma el permiso.

.DESCRIPTION
  Guardar la copia en Android pasa por el Storage Access Framework: la app le
  pide al sistema que el usuario elija una carpeta, y el sistema abre su propio
  selector (DocumentsUI). En una corrida sin nadie delante ese selector se queda
  esperando, y el benchmark con él.

  Este guion hace lo que haría una persona: mira la pantalla con uiautomator,
  entra a la carpeta -Folder, toca «Usar esta carpeta» y después «Permitir». Con
  -PickFile sigue después con el selector de ARCHIVOS —el que se abre al traer
  una copia—: entra a la carpeta y toca ese archivo. Es para un EMULADOR o un
  teléfono de pruebas: lee y toca la pantalla de verdad.

  Se corre en OTRA terminal, antes o justo después de empezar:

      tool/bench_android.ps1 -Target vault_backup_benchmark_test -SaveToFolder
      tool/bench_android_pick_folder.ps1

  Los textos de los botones dependen del idioma del sistema: se reconocen en
  inglés y en español. Si el selector de tu versión de Android es otro, el guion
  imprime lo que ve para poder ajustarlo.

.EXAMPLE
  tool/bench_android_pick_folder.ps1 -Folder Documents
#>
[CmdletBinding()]
param(
  [string] $Device,
  # La carpeta que se elige. Android 11+ no deja elegir la raíz del
  # almacenamiento ni «Download»: una subcarpeta de primer nivel sí.
  [string] $Folder = 'Documents',
  # Si se da, después de elegir la carpeta espera el selector de archivos y toca
  # este archivo (su nombre tal cual se ve en la lista).
  [string] $PickFile,
  # Cuánto se espera, como mucho, a que el selector aparezca y se cierre.
  [int] $TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'

function Find-Adb {
  $fromPath = Get-Command adb -ErrorAction SilentlyContinue
  if ($fromPath) { return $fromPath.Source }
  foreach ($root in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk")) {
    if ($root) {
      $candidate = Join-Path $root 'platform-tools/adb.exe'
      if (Test-Path $candidate) { return $candidate }
    }
  }
  throw 'No encuentro adb: agregá platform-tools al PATH o definí ANDROID_HOME.'
}
$adb = Find-Adb

if (-not $Device) {
  $ready = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' } |
    ForEach-Object { ($_ -split '\s+')[0] })
  if ($ready.Count -ne 1) { throw "Hace falta exactamente un dispositivo (hay $($ready.Count)): elegí uno con -Device." }
  $Device = $ready[0]
}

# Lo que hay en pantalla: cada nodo con texto o descripción, y dónde está.
function Get-Screen {
  # Fuera del almacenamiento compartido: ahí el propio selector lo mostraría.
  $remote = '/data/local/tmp/sinapsis_pick_folder.xml'
  $ErrorActionPreference = 'Continue'
  & $adb -s $Device shell uiautomator dump $remote *> $null
  $raw = & $adb -s $Device shell cat $remote 2> $null
  $ErrorActionPreference = 'Stop'
  $text = ($raw -join "`n")
  if ($text -notmatch '<hierarchy') { return @() }
  $xml = [xml] $text.Substring($text.IndexOf('<hierarchy'))
  foreach ($node in $xml.SelectNodes('//node')) {
    $label = if ($node.text) { $node.text } else { $node.'content-desc' }
    if (-not $label) { continue }
    if ($node.bounds -notmatch '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') { continue }
    [pscustomobject]@{
      Label   = $label
      Package = $node.package
      Enabled = $node.enabled -eq 'true'
      X       = ([int]$Matches[1] + [int]$Matches[3]) / 2
      Y       = ([int]$Matches[2] + [int]$Matches[4]) / 2
    }
  }
}

function Tap($node) {
  Write-Host ("  toca «{0}» en ({1}, {2})" -f $node.Label, $node.X, $node.Y)
  $ErrorActionPreference = 'Continue'
  & $adb -s $Device shell input tap ([int]$node.X) ([int]$node.Y) *> $null
  $ErrorActionPreference = 'Stop'
}

$useFolder = '^(use this folder|usar esta carpeta|usar esta carpeta\.)$'
$allow = '^(allow|permitir)$'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$folderDone = $false
$fileDone = -not $PickFile
$lastSeen = ''

# Se decide por lo que hay en pantalla, no por lo que ya se hizo: el selector
# puede abrir en cualquier carpeta —recuerda la última— y un paso que no se
# nota (o que hizo otra persona) no debe descolocar al resto.
#  - «Permitir» es el permiso de la carpeta: se concede.
#  - Con «Usar esta carpeta» en pantalla es el selector de CARPETAS: si ya se
#    está dentro de -Folder se toca ese botón; si no, se entra a la carpeta.
#  - Sin ese botón es el selector de ARCHIVOS: se toca -PickFile, o se entra a
#    la carpeta que lo tiene.
Write-Host "Esperando el selector en $Device (carpeta «$Folder»$(if ($PickFile) { ", archivo «$PickFile»" }))..."
while ((Get-Date) -lt $deadline -and -not ($folderDone -and $fileDone)) {
  $screen = @(Get-Screen)
  # Solo lo que pertenece al selector del sistema: nada de tocar la app.
  $picker = @($screen | Where-Object { $_.Package -match 'documentsui|permissioncontroller|android$' })
  $seen = ($picker | ForEach-Object { $_.Label }) -join ' | '
  if ($seen -and $seen -ne $lastSeen) { Write-Host "  en pantalla: $seen"; $lastSeen = $seen }

  $allowButton = $picker | Where-Object { $_.Label -match $allow -and $_.Enabled } | Select-Object -First 1
  $treeMode = @($picker | Where-Object { $_.Label -match $useFolder }).Count -gt 0
  $useButton = $picker | Where-Object { $_.Label -match $useFolder -and $_.Enabled } | Select-Object -First 1
  $inside = @($picker | Where-Object { $_.Label -eq "Files in $Folder" -or $_.Label -eq "Archivos en $Folder" }).Count -gt 0
  $folderRow = $picker | Where-Object { $_.Label -eq $Folder } | Select-Object -First 1
  $fileRow = if ($PickFile) { $picker | Where-Object { $_.Label -eq $PickFile } | Select-Object -First 1 }

  if ($allowButton) {
    Tap $allowButton
    $folderDone = $true
    # El diálogo tarda un poco en irse: sin esperar se lo toca varias veces.
    Start-Sleep -Seconds 2
  } elseif ($treeMode) {
    if ($inside -and $useButton) { Tap $useButton }
    elseif (-not $inside -and $folderRow) { Tap $folderRow }
  } elseif ($folderDone -and -not $fileDone -and $picker.Count -gt 0) {
    if ($fileRow) { Tap $fileRow; $fileDone = $true }
    elseif (-not $inside -and $folderRow) { Tap $folderRow }
  }
  Start-Sleep -Seconds 1
}

if (-not $folderDone) {
  throw "El selector de carpetas no se pudo manejar en $TimeoutSeconds s (lo último que se vio: $lastSeen)."
}
if (-not $fileDone) {
  throw "El selector de archivos no se pudo manejar en $TimeoutSeconds s (lo último que se vio: $lastSeen)."
}
Write-Host 'Listo.'
