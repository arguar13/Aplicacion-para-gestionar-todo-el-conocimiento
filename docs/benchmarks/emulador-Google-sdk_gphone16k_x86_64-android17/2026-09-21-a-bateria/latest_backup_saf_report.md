# Copia de la bóveda, por tandas

Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM

Con los selectores del sistema manejados desde afuera: los tiempos de armar y de abrir salen más lentos que en la corrida limpia (`latest_backup_report.md`); lo que esta corrida mide es guardar y elegir la copia.

- la bóveda: 683.2 MB de base, 10000 elementos, y 49.0 MB de originales (12 archivos)
- **armar la copia: 259921 ms**; el .zip pesa 220.4 MB (30 % de lo que ocupan la base y los originales); memoria residente +55.6 MB
- **guardarla en la carpeta elegida con el selector del sistema: 1152 ms** (191 MB/s); quedó en primary:Documents/sinapsis-backup-bench.zip; memoria residente +0.4 MB
- **elegirla con el selector del sistema: 12400 ms**; el selector la copia al almacenamiento temporal de la app (220.4 MB); memoria residente +1.2 MB
- la copia elegida se abre desde su ruta con sus 10000 elementos y, al soltarla, el almacenamiento temporal de la app queda sin ella
- **abrirla (sacar la base a un temporal y dejarla lista): 102692 ms**; memoria residente +45.2 MB
- la copia se lee de vuelta con el CRC de cada entrada verificado: 10000 elementos, 12 originales, un PDF idéntico
- memoria residente máxima del proceso: 415 MB
