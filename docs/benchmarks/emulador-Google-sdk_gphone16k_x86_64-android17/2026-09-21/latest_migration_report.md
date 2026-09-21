# Migración a escala

Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM

- la bóveda de partida: 909 MB, copiada en 3672 ms
- esquema de partida v17; 10000 elementos, 312793 chunks, 10000 formas
- **migración de v17 a v20, con el respaldo previo: 22844 ms** (respaldo: 896 MB)
- los 19 conteos, iguales; tablas nuevas vacías; sin claves rotas
- `verifyChunkInvariant`, entera: 7200 fuentes con texto, 312793 chunks, 0 fuentes sin texto: invariante OK (2506 ms)
- después de migrar: el archivo ocupa 1140.8 MB y 463.0 MB se pueden recuperar; espacio libre 9886.4 MB, la compactación necesita 1507.2 MB (ready)
- **compactación (VACUUM con `temp_store = FILE`, y comprobación): 33643 ms** —reescribir 31338 ms, comprobar 2103 ms—; el archivo pasó de 1140.8 MB a 669.8 MB (devolvió 471.0 MB); 7200 fuentes comprobadas; memoria residente +4.6 MB con 677.8 MB de contenido útil
- memoria residente máxima del proceso: 265 MB
