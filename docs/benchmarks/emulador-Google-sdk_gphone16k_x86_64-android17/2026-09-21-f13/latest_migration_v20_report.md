# Migración a escala

Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM

- la bóveda de partida: 683 MB, copiada en 2487 ms
- esquema de partida v20; 10000 elementos, 314213 chunks, 10000 formas
- **migración de v20 a v21, con el respaldo previo: 1668 ms** (respaldo: 670 MB)
- los 19 conteos, iguales; tablas nuevas vacías; sin claves rotas
- `verifyChunkInvariant`, entera: 7200 fuentes con texto, 314213 chunks, 0 fuentes sin texto: invariante OK (1773 ms)
- después de migrar: el archivo ocupa 683.3 MB y 3.7 MB se pueden recuperar; espacio libre 10039.5 MB, la compactación necesita 1511.2 MB (ready)
- **compactación (VACUUM con `temp_store = FILE`, y comprobación): 11216 ms** —reescribir 8777 ms, comprobar 2423 ms—; el archivo pasó de 683.3 MB a 670.9 MB (devolvió 12.4 MB); 7200 fuentes comprobadas; memoria residente +2.6 MB con 679.6 MB de contenido útil
- memoria residente máxima del proceso: 273 MB
