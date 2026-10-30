# F45 — Pulido del 30/10: avisos, triar, la Biblioteca solo con el original, Procesado y el diseño

> **Estado: APROBADO** (2026-10-30, «Aprobado» en el chat), con las decisiones A a E como están;
> la B, la recomendada, **elegida por el dueño** el 30/10: «Al elegir «Texto extraído» en el
> triaje, la IA de turno lo ordena (columnas, encabezados, cortes y títulos)».
>
> Pedido del dueño, el 30/10, con diez capturas: *"Ahora vamos con una serie de mejoras"* —once,
> con la de la Infografía y la Presentación—. Se construye en paralelo con F44 (el Mapa), en
> pantallas distintas:
>
> - **ola 1**: F44 pasos 1 a 3 y F45 pasos 2 a 4;
> - **ola 2**: F44 pasos 4 y 5 y F45 paso 5;
> - **ola 3**: F45 paso 1, los avisos. Va solo al final porque toca los 179 avisos de toda la app.

## Las once mejoras

### 1. Los avisos de abajo: ordenados, con su ✕ siempre y por encima de todo (1.ª captura)

**Lo que pasa hoy.** «Procesado actualizado: Historia de Heródoto…» con «Ver» al lado del texto,
y «Deshacer» y la ✕ en un renglón aparte, con aire sin sentido. El aviso común (`AppSnackBar`,
F43 M1) admite **un** botón; los que necesitan dos meten el segundo adentro del texto, y Material
los acomoda como puede. Además, el **lector flotante** (el botón redondo de «Leer en voz alta»,
F25) va por encima de toda la app y tapa la ✕.

**Qué se hace.**

- Un solo aviso para toda la app, con **el texto a la izquierda** (hasta tres renglones), **uno
  o dos botones** alineados a la derecha («Ver», «Deshacer») y **la ✕ siempre**, en todos los
  avisos (también los cortos: decisión A).
- Si no entra en un renglón, los botones bajan **juntos**, alineados a la derecha, con la ✕
  arriba a la derecha, como una tarjeta: nunca un hueco en el medio.
- **El lector flotante se corre para arriba** mientras hay un aviso, como un botón flotante de
  Android: el aviso se ve entero y nada tapa la ✕.
- Se pasan **los 179 avisos** de la app al aviso común. El censo de avisos que ya existe
  (`snack_bar_census_test`) exige que ninguno quede afuera.

### 2. «¿Qué va a Procesado?»: el original primero, las imágenes plegadas y el texto al final (2.ª)

- **Orden nuevo:** **El original** → **Imágenes** → **Texto extraído**.
- **Imágenes, plegada**: una fila compacta —«Imágenes · 40 · 4,1 MB · 0 elegidas ▸»— que se
  despliega con la flecha y recién ahí muestra la grilla con «Todas» y «Ninguna».
- **Texto extraído, con la IA de turno** (ver la decisión B): al prenderlo, dice qué IA lo va a
  hacer («Lo extrae Gemini» o «Gemma, en el teléfono») y, al tocar «Listo», la IA arma el texto
  en segundo plano, con el aviso de la cola de siempre.

### 3. La vista previa de una imagen: «Ampliar» en el medio, como el PDF (3.ª)

El botón de las flechitas, hoy en la esquina, pasa **al centro** de la imagen con la píldora de
«Leer como libro» del PDF (el mismo componente, no una copia), con el texto **«Ampliar»**.

### 4. Fuera «Leer» (y su pantalla) en la Biblioteca (4.ª)

La pantalla de lectura del texto extraído («Ninguna nota extraída», «Seleccioná un fragmento…»)
deja de abrirse desde la Biblioteca. Leer, marcar y sacar notas del texto se hace en Procesado. La
pantalla **no se borra**: la sigue usando Procesado.

### 5. El texto en árabe de un video en español (5.ª): la causa de raíz

**Lo que se sabe.** El texto de Procesado es una copia del de la Biblioteca, y el de un video sale
de dos caminos:

- de los subtítulos de YouTube;
- si no hay en qué confiar, de la transcripción del audio en el teléfono.

F22 ya había cerrado un caso así: un video en español con subtítulos subidos en árabe. Desde
entonces nunca se baja una pista en un idioma que no sea el que se habla. Que vuelva a pasar quiere
decir que hay **otro** camino que lo deja entrar, por ejemplo:

- un video **doblado con IA**, cuyo audio «de siempre» YouTube marca en árabe;
- el idioma del título adivinado mal;
- la transcripción del teléfono sin el idioma fijado;
- o una captura anterior a F22.

**Qué se hace.**

1. **Diagnóstico con el video real**: se lee del teléfono solo ese elemento (su enlace y de qué
   pista salió; nada más de la base) y se repite la bajada en la PC. Con la causa a la vista se
   arregla donde está.
2. **Una red de seguridad, pase lo que pase**: antes de guardar un texto de un video, se compara
   su escritura y su idioma con el idioma que se habla. Si no coinciden —árabe en un video en
   español—, **no se guarda**: se transcribe el audio en el teléfono con el idioma fijado, y el
   aviso lo dice.
3. **Arreglar lo ya guardado**: la Bandeja y Procesado ofrecen «Volver a extraer» en los videos
   cuyo texto no está en su idioma, y se puede pedir para todos de una vez.
4. **Nunca un texto inventado**: el texto de un video sale de los subtítulos o del audio, nunca de
   una IA que lo escriba. Si la decisión B hace que una IA ordene el texto, cada palabra se
   comprueba contra lo transcripto (ver B).

### 6. Fuera «Escuchar» de la sección «Texto» de Procesado (6.ª)

Sale el botón de la cabecera de la tarjeta «Texto». **Escuchar sigue** en el lector flotante de
abajo, que lee lo que está en pantalla: es la misma función en un solo lugar.

### 7. Una página web en Procesado, como en el teléfono; y la barra de Resumen y Síntesis (7.ª)

- **Vista móvil**: la página se muestra con el ancho del teléfono (la vista de un navegador móvil,
  sin el menú lateral ni las columnas de escritorio de Wikipedia), no achicada.
- **La barra de arriba, rehecha**:
  - hoy son tres botones grandes («Resumen · Sin hacer», «Síntesis…», «Palabras clave…») y una
    leyenda repetida debajo;
  - pasan a **una sola fila de tres fichas compactas**, del mismo alto, cada una con su color, su
    estado («Hecho», «Sin hacer», «Haciendo…») y un toque para crearla o verla;
  - la leyenda de colores se integra en las mismas fichas (el punto de color es la leyenda);
  - en 360 dp con la letra al doble pasan a dos renglones sin cortarse.

### 8 y 9. La Biblioteca, solo con el original (8.ª y 9.ª)

En el detalle de **cualquier** documento de la Biblioteca salen:

- la fila **Leer · Copiar · Más** (9.ª);
- la tarjeta **«Estudiar el documento»** con Resumir, Sintetizar, Palabras clave, Descargar y
  «Extraer texto» (8.ª).

Se queda **«Se estudia en Procesado… Estudiarlo en Procesado»**, que es la puerta a lo trabajado.

**Lo que había en «Más» no se pierde; cambia de lugar:**

| Antes, en «Más» | Ahora |
|---|---|
| Organizar con IA, buscar fechas | ya eran de Procesado (F41, decisión K) |
| Volver a extraer, quitar marcas de tiempo | en Procesado, sobre su texto |
| Soltar el texto de un libro | en Procesado |
| Pantalla completa | el «Ampliar» del centro de la vista previa (punto 3) |

### 10. La tarjeta de triar de la Bandeja y su barra (10.ª)

- **La barra de arriba**:
  - el ↶ de deshacer se confunde con «volver»; pasa a **«Deshacer» con el ícono de historial**
    (reloj con flecha) y su texto al costado en pantallas anchas;
  - «1 pendiente» queda como una ficha.
- **La tarjeta, ordenada por lo que se hace**:
  1. **La decisión** en una fila fija abajo, a lo ancho: **Descartar** (con borde) · **Triar**
     (relleno, la principal), del mismo alto y alineados.
  2. **Lo demás**, en un renglón de botones con ícono —«Pasar todo», «Extraer nota» y
     «Vincular»—; en angosto, en un menú «⋯».
  3. «Se encontraron datos de la referencia» como un aviso compacto dentro de la tarjeta, con
     «Usar» y la ✕.
  4. «Ver completo» al pie del texto, como un enlace.
  5. Los atajos de teclado solo en la computadora, en una línea gris.
- En 360 dp con la letra al doble, claro y oscuro, con el lector de pantalla.

### 11. La Infografía y la Presentación, más versátiles

Hoy (F43): 16 plantillas y 12 diseños de diapositiva; 18 estilos y 10 composiciones de infografía.

- **Presentación**:
  - **+12 plantillas** (Editorial, Suizo, Bauhaus, Pizarra, Revista, Académica, Minimal oscuro,
    Acuarela, Neón, Corporativa, Retro, Manuscrito);
  - **+8 diseños de diapositiva** (cita a toda página, línea de tiempo, comparación en dos
    columnas, número grande, cuadrícula de imágenes, proceso en pasos, mapa de conceptos, cierre
    con preguntas);
  - **personalizar**: la paleta (de la plantilla o una propia con un color de base), la pareja de
    letras, la densidad y el fondo (liso, degradado o con textura);
  - cambiar de plantilla en el visor, sin volver a llamar a la IA.
- **Infografía**:
  - **+12 estilos**;
  - **+6 composiciones** (línea de tiempo vertical, comparación, embudo, ciclo, mapa de temas,
    estadísticas en mosaico);
  - **+4 gráficos** (anillos, barras horizontales, pictograma y escala);
  - el mismo «personalizar» de colores, letras y fondo.
- Todo cabe en el teléfono, se exporta a PNG y PDF como hoy y respeta claro y oscuro.

## Decisiones (se pueden cambiar mientras no se llegue a su paso)

- **A. La ✕ en todos los avisos**, también en los cortos («Copiado»). Pedido literal: «para que se
  pueda sacar siempre». Cambia la regla de F43 M1, que la ponía solo en los largos o con botón.
- **B. «Texto extraído» al triar: la IA de turno lo arma, con la extracción de siempre como
  base.** *(Elegida por el dueño el 30/10.)*
  - **Recomendada:**
    - la app sigue sacando el texto por su cuenta, como hoy, pero ya no se muestra en la
      Biblioteca; lo siguen usando por dentro la búsqueda, el chat y los vínculos;
    - al elegir «Texto extraído» al triar, la IA de turno lo **ordena**: une las columnas, saca
      encabezados y pies de página repetidos, arregla los cortes y marca los títulos;
    - cada palabra se comprueba contra la extracción: si la IA inventa, resume o traduce, se queda
      la extracción tal cual y el aviso lo dice.
  - *Alternativa:* que la IA lea el archivo desde cero (Gemini, OpenAI y Claude leen PDF e
    imágenes). No la recomiendo: cuesta mucho más con un libro, no anda con Gemma en el teléfono,
    y es justo lo que puede inventar o traducir (punto 5).
- **C. El lector flotante se corre arriba del aviso**, en lugar de esconderse: sigue a la vista y
  a un toque.
- **D. La web en Procesado se muestra con el ancho del teléfono** también en la computadora,
  dentro de su tarjeta.
- **E. Nada se borra de la Biblioteca** (la regla de siempre): sale lo que se **muestra**, no los
  datos. El texto extraído de cada fuente sigue guardado.

## Pasos (cada uno, su commit y su push)

Una ola de cinco agentes en paralelo, cada uno en su rama, con su GUÍA, sus pruebas y sus
mutaciones; se integran en `main` de a uno, con su suite, su push y su verificación.

1. **Los avisos** (1, decisiones A y C): el aviso común con dos botones y la ✕, los 179 avisos
   pasados a él con su censo, y el lector flotante que se corre.
2. **Triar** (2 y 10, decisión B): la hoja «¿Qué va a Procesado?» con el orden nuevo, Imágenes
   plegada y Texto extraído con la IA comprobada palabra por palabra; la tarjeta y la barra de la
   Bandeja.
3. **La Biblioteca, solo el original** (3, 4, 8 y 9, decisión E): «Ampliar» en el medio, fuera
   «Leer», la fila de acciones y «Estudiar el documento», y lo de «Más» mudado a Procesado.
4. **Procesado** (5, 6 y 7): el diagnóstico del árabe con el video real, la red de seguridad del
   idioma, «Volver a extraer» para lo ya guardado, fuera «Escuchar», la web en vista móvil y la
   barra de Resumen y Síntesis.
5. **El diseño** (11): las plantillas, diseños, estilos, composiciones y gráficos nuevos, y
   «Personalizar» en la Presentación y la Infografía.
6. **El cierre**: la suite entera, la decisión 91 en arquitectura, la GUÍA y la APK al teléfono si
   la pedís.

## Lo que no entra (para que quede dicho)

- **Borrar el texto extraído que ya está guardado** en la Biblioteca: deja de mostrarse, no se
  borra (decisión E).
- **Traducir**: ningún texto extraído se traduce; siempre queda en el idioma de la fuente.

## Avance

(vacío: se llena con cada paso)
