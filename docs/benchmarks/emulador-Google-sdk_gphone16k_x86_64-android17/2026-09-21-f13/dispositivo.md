# Dispositivo

- Tipo: EMULADOR (los tiempos son de la máquina anfitriona; las cifras de
  memoria sí valen)
- Modelo: Google sdk_gphone16k_x86_64
- Android: 17 (API 37)
- SoC: ranchu
- RAM: 3.8 GB
- Libre en /data al empezar: entre 11 y 13.5 GB
- PC anfitriona: ENCHUFADA en las dos corridas de esta carpeta (los 24
  escenarios y la migración de v20 a v21); el guion no avisó de batería en
  ninguna
- Temperatura de la batería al empezar: 25 °C (cargando: True)
- Flavor: staging (app.sinapsis.staging), modo profile
- Fecha: 2026-09-21

La migración de v17 a v21 (909 MB) NO está acá: esa corrida salió con la PC
funcionando a batería —el cable se desconectó entre una corrida y la
siguiente— y está en `../2026-09-21-f13-a-bateria/`. Falta repetirla
enchufada; la migración de v20 a v21, que es el salto que agrega F13, sí
salió enchufada.

Entre corridas el emulador se reinició: en la primera migración de v20 a v21
el sistema mató la aplicación (`lowmemorykiller`, «min watermark is
breached») al empezar la compactación, tras varias corridas seguidas y 2,4 GB
empujados con `adb`; con el emulador reiniciado la misma corrida terminó. Es
memoria del emulador (3,8 GB) llena de caché de archivos, no de la aplicación,
que llegó a 273 MB de residente máximo.
