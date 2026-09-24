# Benchmark de la bóveda con referencias

Esquema v22
Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM
Umbral: objetivo del encargo

```
detalle: fuente con referencia y cita          frío      4 ms   mediana      0 ms   objetivo 200 ms
referencia por DOI                             frío      0 ms   mediana      0 ms   objetivo 10 ms
referencia por ISBN                            frío      0 ms   mediana      0 ms   objetivo 10 ms
bibliografía APA de la rama mayor              frío    474 ms   mediana    432 ms   objetivo 3000 ms
bibliografía de la rama mayor a .docx          frío    191 ms   mediana    187 ms   objetivo 4000 ms
autores: candidatos a fusionar                 frío    231 ms   mediana    204 ms   objetivo 1000 ms
exportar 10.000 a BibTeX                       frío    712 ms   mediana    649 ms   objetivo 5000 ms
exportar 10.000 a RIS                          frío    606 ms   mediana    633 ms   objetivo 5000 ms
importar 5.000 entradas (crear)                frío   4927 ms   mediana   4927 ms   objetivo 90000 ms
reimportar 5.000 entradas (sin cambios)        frío   2157 ms   mediana   2157 ms   objetivo 30000 ms
```
