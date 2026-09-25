# Benchmark de la bóveda con referencias

Esquema v28
Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM
Umbral: objetivo del encargo

```
detalle: fuente con referencia y cita          frío      5 ms   mediana      0 ms   objetivo 200 ms
referencia por DOI                             frío      0 ms   mediana      0 ms   objetivo 10 ms
referencia por ISBN                            frío      0 ms   mediana      0 ms   objetivo 10 ms
bibliografía APA de la rama mayor              frío    407 ms   mediana    404 ms   objetivo 3000 ms
bibliografía de la rama mayor a .docx          frío    147 ms   mediana    179 ms   objetivo 4000 ms
autores: candidatos a fusionar                 frío    198 ms   mediana    197 ms   objetivo 1000 ms
exportar 10.000 a BibTeX                       frío    608 ms   mediana    604 ms   objetivo 5000 ms
exportar 10.000 a RIS                          frío    602 ms   mediana    637 ms   objetivo 5000 ms
importar 5.000 entradas (crear)                frío   4493 ms   mediana   4493 ms   objetivo 90000 ms
reimportar 5.000 entradas (sin cambios)        frío   2109 ms   mediana   2109 ms   objetivo 30000 ms
```
