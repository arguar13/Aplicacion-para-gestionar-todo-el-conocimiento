<#
.SYNOPSIS
  Corre la suite completa sobre una COPIA del proyecto, sin molestar al árbol de trabajo.

.DESCRIPTION
  Copia el proyecto a `%TEMP%\sinapsis-suite` (sin `.git`, `build`, `.dart_tool` ni las copias de los
  agentes) y corre `flutter test` ahí, dejando el registro en `%TEMP%\sinapsis-suite-<Log>`.

  Por qué una copia: se puede seguir editando y commiteando mientras la suite corre (tarda unos
  30-45 minutos). El registro empieza con `COPIADO` cuando terminó de copiar —desde ahí es seguro
  tocar el árbol de trabajo— y termina con `EXIT <código>`.

  Las pruebas de memoria de la suite son sensibles a la carga de la máquina: no correr otra cosa
  pesada a la vez (una falla suelta de `incoming_vault_file_test` o `sqlite_vault_compactor_...`
  que pasa sola, una por una, es de carga y no un defecto).

.PARAMETER Log
  Nombre del registro (sin ruta).
#>
param([string] $Log = 'run.log')

$src = Split-Path -Parent $PSScriptRoot
$dst = Join-Path $env:TEMP 'sinapsis-suite'
$logPath = Join-Path $env:TEMP "sinapsis-suite-$Log"
$ErrorActionPreference = 'Continue'

robocopy $src $dst /MIR /XD .git .dart_tool build .idea .pdfium .claude .github /NFL /NDL /NJH /NJS /NP | Out-Null
'COPIADO' | Out-File -Encoding utf8 $logPath
Set-Location $dst
flutter pub get *> $null
flutter test --timeout 150s --reporter expanded *>&1 | Out-File -Encoding utf8 -Append $logPath
"EXIT $LASTEXITCODE" | Out-File -Encoding utf8 -Append $logPath
