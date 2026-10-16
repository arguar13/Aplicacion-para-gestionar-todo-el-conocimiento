# F32 — La IA en la nube: Gemini gratis por defecto, varias cuentas y un solo lugar

> **Estado: aprobado** (2026-10-16), en el chat, con estos cambios a las recomendadas:
>
> - **Nada del contenido se guarda en la nube**: la bóveda, los archivos, las copias y el historial
>   quedan siempre en el teléfono. Lo único que sale es el texto que la IA tiene que leer en cada
>   pedido (elegido por el usuario entre las opciones, sabiendo que en la capa gratuita Google puede
>   guardarlo y leerlo).
> - **Un solo modelo para todo**: el elegido hace todo lo que hoy hace Gemma, sin repartir tareas
>   entre Gemma y la nube. Si se acaban las cuentas, se espera; no se cae a Gemma en silencio.
> - **B, la alternativa**: al agotarse la cuota, **cambia sola a la siguiente cuenta y avisa**, con la
>   mayor retroalimentación posible. El usuario conoce y acepta el riesgo de la sección 2(d).
> - **Todo ultra elegante y visualmente cuidado.**
> - A (con el tope de la IA de fondo), C, D y E: las recomendadas.
>
> Pedido del usuario: *"quiero que usemos gemini la capa gratuita … la idea es usar api keys
> generadas en google ai studio para que mi modelo central sea el de gemini así sea más rápido y
> más inteligente … que me deje usar varias cuentas de google … un menú desplegable … con un solo
> click cambie de cuenta pero todo mi backend y mi app no cambie … que eso del modelo y la api key
> sea centralizado … que también sea compatible para cuentas de claude o de open ai, si el día de
> mañana quiero pagar … pero por defecto quiero usar siempre gemini con la capa gratuita"*.

## Lo que hay hoy (relevado en el código)

| Qué | Cómo está |
|---|---|
| **El modelo de lenguaje** | Uno solo: Gemma 4 E4B, que se baja (~3,7 GB) y corre en el teléfono. Es opcional: sin él, la IA no hace nada. |
| **Quién lo usa** | El chat, resumir, las tarjetas, los huecos con IA, el quiz, los vínculos sugeridos, las propiedades, las notas derivadas, los cuadernos con IA y **la IA que organiza sola** (de fondo, aun con la app cerrada). |
| **Cómo está armado** | Cada una de esas funciones ya es una pieza aparte (una interfaz), y hoy **todas las cumple una sola clase**, la de Gemma. Las pantallas no saben qué modelo hay detrás: cambiar el motor no obliga a rehacerlas. |
| **Textos largos** | Gemma lee de a poco (2.048 tokens de ventana): un libro se parte en pedazos de **3.000 caracteres**. Es lento y cada pedazo ve poco del resto. |
| **Lo que no es de este modelo** | El motor de relaciones (los vectores de parecido y los duplicados), Whisper (transcribir) y el OCR son otros modelos, también locales. |

## Lo que dice Google (verificado el 16/10/2026)

- **No hace falta iniciar sesión con Google adentro de la app.** Alcanza con una **clave de API**
  que se genera en Google AI Studio (aistudio.google.com) con cada cuenta. La app guarda las claves,
  no tus contraseñas.
- **La cuota se cuenta por proyecto, no por clave**: dos claves del mismo proyecto comparten el
  mismo límite. Para tener otra cuota hace falta otro **proyecto** (en la práctica, otra cuenta).
- **La capa gratuita es de los modelos «Flash»** (los «Pro» quedaron solo pagos), con un tope por
  minuto y otro **por día** que Google cambió varias veces este año. Las cifras públicas no
  coinciden entre sí; la app no las va a escribir en el código: le pregunta a Google qué modelos hay
  y **mide lo que vos gastás**. Tu cuota real se ve en AI Studio.
- **Lo que mandás a la capa gratuita, Google lo puede usar para mejorar sus productos, y personas
  de Google pueden leerlo** («Do not submit sensitive, confidential, or personal information to the
  Unpaid Services», términos de la API de Gemini). La capa paga no. Esto choca con el principio 1
  de Sinapsis («todo ocurre en el dispositivo»): ver la decisión A.
- **Rotar cuentas para estirar la cuota gratuita va contra los términos de las APIs de Google**
  (sección 2(d): *"You agree to, and will not attempt to circumvent, such limitations"*), y Google
  *"may suspend access to the APIs … without notice"*. Tener varias cuentas no está prohibido;
  usarlas a propósito para pasar el tope, sí. Ver la decisión B: es tu riesgo, y te lo digo antes.

## Qué se construye

1. **Un solo lugar: Ajustes → «IA y modelos» → «Modelo de lenguaje».**
   - Elegís el **proveedor**: **Gemini** (por defecto), **Gemma en el teléfono** (como hoy),
     **OpenAI** o **Claude** (de pago, para el día que quieras comprar créditos).
   - Cada proveedor tiene sus **cuentas**: un nombre que vos le ponés (*«armando@gmail.com»*,
     *«cuenta 2»*) y su clave. **«Probar»** comprueba que la clave ande con un pedido mínimo.
   - **El modelo** se elige de la lista que el propio proveedor devuelve con esa clave (no una lista
     fija que envejece); por defecto, el Flash más nuevo de la capa gratuita.
   - **Lo gastado hoy** con cada cuenta (pedidos y tokens, contados por la app) y el último aviso
     de cuota agotada, con la hora a la que se renueva.
2. **Cambiar de cuenta con un toque.** Un menú desplegable con todas tus cuentas, en ese lugar y
   arriba del chat. Cambiar de cuenta **no cambia nada más**: tu bóveda, tus tarjetas, tu historial
   y la configuración siguen iguales; solo cambia qué clave se usa desde el próximo pedido.
3. **Todo lo que hoy hace Gemma lo hace el modelo elegido**, con respuesta a medida que se escribe
   en el chat, fotos en el chat (Gemini, OpenAI y Claude las aceptan), y botón «Detener».
4. **Textos largos de una sola vez.** Las partes se miden con la ventana del modelo elegido: con
   Gemini, un capítulo o un libro chico entra entero en vez de en 3.000 caracteres; Gemma sigue
   igual que hoy.
5. **Cuando se agota la cuota, o no hay internet** (ver decisión B):
   - La app te lo dice con claridad (*«Se terminó la cuota gratuita de "cuenta 1" por hoy; se renueva
     a las 4:00»*) y te ofrece **cambiar de cuenta**.
   - **Decidido:** pasa sola a la siguiente cuenta con cuota y te avisa (qué cuenta se agotó, a cuál
     pasó, cuándo se renueva la primera). Si no queda ninguna, te lo dice y espera; no cambia a
     otro modelo sin que vos lo elijas.
   - La IA de fondo **espera** a que vuelva la cuota (no se pierde nada: ya funciona así cuando el
     modelo falta), y retoma sola.
6. **La IA de fondo no te come la cuota.** Un tope de pedidos por día para la IA que organiza sola
   (cambiable), para que siempre te quede para el chat y lo que pedís a mano; pasado el tope, sigue
   al día siguiente.
7. **Avisos de privacidad donde corresponde**: la primera vez que elegís un proveedor en la nube, la
   app te explica qué se manda (el texto de lo que la IA lee) y qué no (tu clave de la bóveda, tus
   archivos que la IA no usa). En la pantalla del modelo queda a la vista si la IA es **local** o
   **en la nube**.

## Decisiones que necesito que confirmes

- **A. Qué va a la nube.**
  - *(Recomendado)* **Todo lo que hoy hace Gemma**, también la IA de fondo, con el tope diario del
    punto 6. Es lo que hace la app más rápida e inteligente, que es lo que pediste. Sabiendo que,
    en la capa gratuita, Google puede leer y usar lo que mandás.
  - Alternativa: **solo lo que pedís vos** (chat, resumir, tarjetas, quiz…); la IA de fondo sigue
    con Gemma local o no corre. Menos de tu bóveda sale del teléfono, y la cuota rinde más.
- **B. Cuando se agota la cuota de una cuenta.**
  - *(Recomendado)* **Te avisa y cambiás vos, con un toque**, y mientras tanto sigue con Gemma si
    está bajado. Tener varias cuentas y elegir cuál usar es tuyo.
  - Alternativa: **cambia sola a la siguiente cuenta** con cuota. Es lo que describiste, pero es
    exactamente lo que la sección 2(d) de los términos de Google prohíbe, y Google puede cortar el
    acceso a la API de esas cuentas sin aviso. Si la elegís, la construyo, y queda dicho en la guía.
- **C. Dónde se guardan las claves.**
  - *(Recomendado)* **En el almacén seguro del teléfono** (el mismo de la clave de la bóveda), fuera
    de la base y de las copias de seguridad. Si desinstalás la app, se van con ella y hay que volver
    a pegarlas (son fáciles de regenerar en AI Studio).
  - Alternativa: **también viajan en la copia de seguridad de la bóveda, cifradas** con tu clave:
    restaurar una copia trae las cuentas. Una copia robada junto con tu clave expondría tus claves.
- **D. Los otros modelos locales.**
  - *(Recomendado)* **Siguen en el teléfono**: el motor de relaciones (parecidos y duplicados),
    Whisper y el OCR. Cambiarlos a Gemini obligaría a rehacer todo el índice de parecidos de tu
    bóveda y gastaría la cuota en cada elemento nuevo.
  - Alternativa: transcribir audios con Gemini (más rápido que Whisper en el teléfono), como una
    opción más adelante, en otra tanda.
- **E. OpenAI y Claude.**
  - *(Recomendado)* **Incluidos ya**, en el mismo lugar y con el mismo menú de cuentas, sin usarse
    hasta que los elijas. Son de pago: la app no tiene forma de saber tu saldo, solo lo que gastaste
    con ella.
  - Alternativa: solo Gemini por ahora, y los otros en otra tanda.

## Lo que cambia por dentro

- **Una sola forma de hablar con cualquier modelo.** Lo que hoy está metido en la clase de Gemma
  —cómo se le pide cada tarea y cómo se lee lo que contesta— se separa del motor. Abajo quedan
  motores intercambiables: Gemma (el de hoy), Gemini, OpenAI y Claude, que solo saben «mandar esto y
  devolver lo que se escribe». Así las diez funciones se escriben **una vez** y valen para todos.
- **Sin paquetes nuevos de cada empresa**: los tres proveedores en la nube se hablan por HTTP con
  `dio`, que la app ya usa (decisión 3: librerías abiertas, nada que se rompa cuando un SDK cambia).
- **El turno de uso** (la persona antes que la IA de fondo) sigue igual; con la nube, además, un
  límite de pedidos por minuto para no recibir rechazos de Google.
- **Los avisos de «falta bajar el modelo»** (están en quince pantallas) pasan a decir lo que de
  verdad falta: bajar Gemma, o cargar una clave, o que no hay internet, o que se acabó la cuota.
- **La base de datos no cambia.** Las cuentas y lo gastado van en el almacén seguro y en las
  preferencias del teléfono.
- **El principio 1 de la arquitectura** se reescribe: *todo ocurre en el dispositivo, salvo que vos
  elijas un modelo en la nube*; la decisión 74 lo deja escrito.

## Orden de trabajo

1. Separar las tareas del motor, sin cambiar nada visible (con Gemma todo sigue igual; la suite lo
   prueba).
2. Las cuentas y las claves: el almacén seguro, la pantalla «Modelo de lenguaje», «Probar», el menú
   desplegable.
3. Gemini: pedidos con respuesta a medida que se escribe, fotos, la lista de modelos, la cuota y sus
   errores, el límite por minuto, lo gastado hoy.
4. Usar el modelo elegido en toda la app: los avisos de las quince pantallas, la IA de fondo con su
   tope, seguir con Gemma cuando falta la nube, y las partes según la ventana.
5. OpenAI y Claude.
6. Pruebas (sin llamar de verdad a ninguna empresa: con respuestas grabadas), comprobadas por
   mutación; la guía de uso; la decisión 74; y la prueba en tu teléfono contigo, con tu clave real.

## Fuentes

- Límites de la API de Gemini: https://ai.google.dev/gemini-api/docs/rate-limits («Rate limits are
  applied per project, not per API key»).
- Términos de la API de Gemini (uso de lo enviado en la capa gratuita, mayoría de edad, regiones):
  https://ai.google.dev/gemini-api/terms
- Términos de las APIs de Google, sección 2(d) (no eludir los límites):
  https://developers.google.com/terms

## Avance (para retomar en otra sesión)

Se actualiza con cada commit. Lo que está acá es la verdad sobre en qué quedó F32.

### Paso 1 — separar las tareas del motor (hecho, sin cambios visibles)

- `lib/features/chat/domain/services/model_backend.dart`: el contrato del motor.
  `ModelBackend` (`contextTokens`, `isWarm`, `warmUp`, `openExchange`, `openConversation`),
  `ModelExchange` (un pedido de una vuelta: `countTokens`, `reply`, `stop`, `close`) y
  `ModelConversation` (una charla con memoria: `send` → `ChatReplyStream`, `close`). El nombre
  `LanguageModelBackend` NO se puede usar: ya es el enum GPU/CPU de F30
  (`language_model_performance.dart`).
- `lib/features/chat/data/services/language_model_tasks.dart`: `LanguageModelTasks`, las diez
  interfaces de IA (`ChatModel`, `FlashcardGenerator`, `ClozeGenerator`,
  `RelationSuggestionService`, `SummarizationService`, `PropertySuggestionService`,
  `DerivedNoteGenerator`, `QuizQuestionGenerator`, `NotebookCandidateJudge`, `NotebookNamer`) más
  `chooseSpace`, `chooseTopicParent` y `writeMapIntroduction`, con todos los prompts, los topes
  de largo (`kChatReplyTokens`, `draftsReplyTokens`…), el turno (`LanguageModelGate`) y el corte
  de la IA de fondo cuando la persona pide el modelo (`background`, `_preempt`). Se generó del
  `GemmaChatModel` de antes con un script que exigía que cada patrón apareciera (12 tareas): los
  prompts son textuales.
- `lib/features/chat/data/services/gemma_backend.dart`: `GemmaBackend`, el motor de Gemma
  (`GemmaEngine` + `createChat` + `collectReply`; las charlas son `GemmaChatSession`, que ahora
  `implements ModelConversation`).
- `gemma_chat_model.dart` quedó como `GemmaChatModel extends LanguageModelTasks` con el mismo
  constructor de siempre (así sus pruebas siguen valiendo) y reexporta `language_model_tasks.dart`.
- `backgroundLanguageModelProvider` ahora es `Provider<LanguageModelTasks>`.

### Paso 2a — el dominio de cuentas y cuota (hecho)

Módulo nuevo `lib/features/ai_models/` (de acá en más, todo lo de F32 que no sea el motor vive acá):
`AiProvider` (gemini, gemma, openAi, anthropic; `isCloud`, `keysUrl`, `storageKey` estable),
`AiAccount` (id, proveedor, nombre, cuándo se agregó; **la clave no va en la entidad**),
`AiModelSettings` (proveedor activo, cuenta activa y modelo por proveedor, `autoSwitchAccounts`
= true, `backgroundDailyCap` = 100), `CloudModelInfo`, `CloudModelException` /
`CloudModelFailure` (invalidKey, forbidden, rateLimited, quotaExhausted, modelNotFound,
unavailable, blocked, network, tooLong, noAccount, unknown), `AccountUsage` (pedidos, tokens,
`exhaustedUntil`), los contratos `AiAccountRepository` (claves en el almacén seguro) y
`AiUsageLedger`, y `quota_day.dart`: la cuota de Gemini se renueva a la **medianoche del
Pacífico** (UTC−8 / UTC−7 con el horario de verano de EE. UU.), calculada sin base de zonas.
Decisiones técnicas tomadas: **`generateContent`** (no la API «Interactions», que guarda las
charlas en los servidores de Google por defecto); `thinkingLevel: low` en Gemini 3/4 y
`thinkingBudget: 0` en 2.5, con margen en el tope (el pensamiento cuenta dentro de
`maxOutputTokens`); la lista de modelos se pide a Google (cambian cada pocos meses: hoy
`gemini-3.8-flash` general y `gemini-3.5-flash-lite` el más barato); cliente HTTP propio para la
IA, sin el registro de red de la app, y la clave en la cabecera `x-goog-api-key`, nunca en la URL.

### Paso 2b — guardar cuentas, lo gastado y lo elegido (hecho)

`lib/features/ai_models/data/repositories/`: `SecureAiAccountRepository` (lista en
`ai_accounts_v1` y cada clave en `ai_key_<id>` del almacén seguro; escrituras en fila;
«Cuenta N» por proveedor si no hay nombre), `PrefsAiUsageLedger` (`ai_usage_<id>` en
SharedPreferences, solo el día de cuota en curso; la marca de agotada cruza el día si el
proveedor lo dijo) y `PrefsAiModelSettingsStore` (`ai_model_settings_v1`, un JSON; lo ilegible
vuelve a lo de fábrica de a un campo). Pruebas: `test/features/ai_models/` (34). **Trampa del
analizador:** un comentario cuya línea empieza con «Todo…» dispara `flutter_style_todos`
(lo toma por un TODO): reformular.

### Paso 3a — el formato de Gemini (hecho)

`lib/features/ai_models/data/cloud/`: `CloudWire` (el contrato de un proveedor en la nube:
`listModels`, `recommendedModel`, `stream` de `CloudDelta`; `CloudRequest` / `CloudMessage`),
`sse.dart` (lector de eventos SSE que no parte UTF-8, común a Gemini, OpenAI y Claude) y
`GeminiWire`: `POST …/v1beta/models/<modelo>:streamGenerateContent?alt=sse`, clave en
`x-goog-api-key`; cuerpo `systemInstruction` + `contents` (roles `user`/`model`, fotos en
`inlineData`) + `generationConfig` (`maxOutputTokens` + 2048 de margen si el modelo piensa;
`thinkingConfig`: `thinkingLevel: low` en 3/4, `thinkingBudget: 0` en 2.5 Flash/Lite, nada en
2.5 Pro); se saltean las partes `thought: true`; los tokens salen de `usageMetadata` (con
`thoughtsTokenCount`). Errores: 429 con `quotaId` «PerDay» → `quotaExhausted` hasta la
medianoche del Pacífico; otro 429 → `rateLimited` con `RetryInfo.retryDelay`;
`API_KEY_INVALID`/401 → `invalidKey`; 403 y `FAILED_PRECONDITION` (región) → `forbidden`;
404 → `modelNotFound`; tokens de más → `tooLong`; 5xx → `unavailable`; sin red → `network`;
`promptFeedback.blockReason` o un fin `SAFETY`… sin texto → `blocked`. La lista de modelos
recorre todas las páginas y deja solo los de texto; el recomendado es el Flash estable más
nuevo. Pruebas: `gemini_wire_test.dart` con un Google falso (`HttpClientAdapter`). Mutaciones:
11/11 muertas con `mutar.py` (en el scratchpad; el método: el texto debe aparecer una sola vez,
se aplica, se corre, se cuenta y se restaura siempre).

### Paso 3b — el motor en la nube con la rotación de cuentas (hecho)

`lib/features/ai_models/data/cloud/cloud_model_backend.dart`: `CloudModelBackend implements
ModelBackend` sobre cualquier `CloudWire`. Elige la cuenta (la elegida del proveedor o la
primera; con `autoSwitchAccounts`, da la vuelta desde la elegida por las demás y saltea las
agotadas); ante `quotaExhausted` marca la cuenta hasta su renovación (Gemini: medianoche del
Pacífico; pagos: 1 h), pasa a la siguiente, **la guarda como elegida** y emite
`AccountSwitchedNotice`; si no queda ninguna, `AllAccountsExhaustedNotice` y falla con la
renovación más cercana; `rateLimited` ≤ 60 s espera avisando (`RateLimitWaitNotice`, hasta 3
veces), más que eso cuenta como agotada; `invalidKey`/`forbidden` → `AccountKeyRejectedNotice`
y la deja de lado 10 min; `unavailable` reintenta una vez a los 2 s; **nunca cambia de cuenta
después de haber escrito texto**. `forBackground` (nuevo en `ModelBackend`; Gemma devuelve el
mismo) cuenta aparte y topea `backgroundDailyCap` (`BackgroundCapReachedNotice`,
`CloudModelFailure.backgroundCap`). Las charlas reenvían lo conversado (el proveedor no guarda
nada), sin repetir eventos. `cloud_model_catalog.dart`: la lista de modelos guardada 3 días en
`ai_models_cache_<proveedor>`, el elegido o el recomendado. Los avisos: `ai_notice.dart`
(sealed). Pruebas: `cloud_model_backend_test.dart` (proveedor falso por clave). Mutaciones: 14/14
muertas (una sobrevivió primero —el cambio automático apagado con la cuenta ya agotada— y se
agregó su prueba). `tool/mutar.py` quedó en el repo: `python tool/mutar.py <mutaciones.json>`.

### Paso 4a — el motor elegido en toda la app (hecho)

- `lib/features/ai_models/presentation/providers/ai_models_providers.dart`: `aiDioProvider` (cliente
  HTTP propio de la IA: sin `NetworkLoggingInterceptor` —no anota URLs— ni
  `GlobalErrorInterceptor` —un 429 lo resuelve el motor—), `aiAccountRepositoryProvider`,
  `aiAccountsProvider` (stream), `aiUsageLedgerProvider`, `aiUsageChangesProvider`,
  `aiNoticeBusProvider` (`AiNoticeBus`, en `domain/services/`), `cloudWiresProvider` (hoy solo
  Gemini), `cloudModelCatalogProvider` y `aiModelSettingsProvider` (`AiModelSettingsNotifier`:
  `save`, `chooseProvider`, `chooseAccount` —**elegir a mano una cuenta le borra la marca de
  agotada**: quien elige sabe algo que la app no—, `chooseModel`, `setAutoSwitch`,
  `setBackgroundDailyCap`).
- `chat_providers.dart`: `modelBackendProvider` elige `GemmaBackend` o `CloudModelBackend` según
  el proveedor y **se rearma solo al cambiar de proveedor** (`select`); cambiar de cuenta o de
  modelo vale desde el próximo pedido. Sobre él, `_languageModelProvider` (`LanguageModelTasks`)
  reemplaza al `_gemmaModelProvider`. Si un proveedor no tiene `CloudWire`, `StateError`: no se
  cae a Gemma en silencio.
- `languageModelStatusCheckProvider` (`LanguageModelStatusCheck`, en
  `domain/services/language_model_readiness.dart`) y `languageModelStatusProvider` (para dibujar):
  `LanguageModelReady`, `LanguageModelNeedsDownload` (Gemma sin bajar),
  `LanguageModelNeedsAccount`, `LanguageModelOutOfQuota` (con la renovación más cercana y si lo
  que falla son las claves) y `LanguageModelBackgroundCapReached` (solo para la IA de fondo). Lo
  calcula `AiLanguageModelReadiness` con las mismas reglas con que el motor elige la cuenta.
- El motor avisa `AiRequestFailedNotice` cuando un pedido **de la persona** falla por algo que otra
  cuenta no arregla (sin red, saturado, modelo inexistente, bloqueado, largo), también si falla
  después de escribir; si eso fue la cuota, la cuenta queda marcada para el pedido siguiente. Sin
  el cambio automático, un tope por minuto largo avisa `AllAccountsExhaustedNotice`.
- `test/support/library_harness.dart` arranca con **Gemma** elegido (parámetro
  `languageModelProvider`) y el almacén seguro en memoria: las pruebas de pantalla de siempre
  siguen midiendo «con el modelo bajado / sin bajar».
- Pruebas: `ai_language_model_readiness_test.dart`, `ai_models_providers_test.dart` y tres nuevas
  del motor. Mutaciones: 14/14 muertas. `tool/mutar.py` estaba roto en el commit anterior (una
  barra sin escapar): arreglado.

### Paso 4b — la pantalla «Modelo de lenguaje», el menú de cuentas y los avisos (hecho)

- Ruta `RoutePaths.languageModel` (`/settings/language-model`): `LanguageModelScreen`
  (`lib/features/ai_models/presentation/screens/`). Encabezado con degradé: proveedor, modelo,
  «En la nube / En el teléfono», «Gratis / De pago», un punto de color con el estado
  (`languageModelStatusProvider`) y el menú de cuentas. Tarjetas de proveedor (OpenAI y Claude
  solo aparecen cuando `cloudWiresProvider` tiene su formato). En la nube: cuentas (tocar una la
  elige; menú Probar / Renombrar / Cambiar la clave / Borrar; lo gastado hoy; «Sin cuota hasta las
  4:00 de mañana»; «Clave rechazada»), el modelo de la lista del proveedor con «Actualizar», la
  cuota (cambio automático con la advertencia de la sección 2(d) y el tope de la IA de fondo:
  25/50/100/200/500/sin tope) y qué sale del teléfono. Con Gemma: «Bajar o cambiar el modelo»
  lleva a la `ChatModelScreen` de siempre.
- **El aviso de privacidad** sale la primera vez que se elige un proveedor en la nube **o que se
  carga su primera clave** (Gemini viene elegido de fábrica: si no, nunca se vería). Se recuerda
  en `ai_cloud_privacy_seen_<proveedor>`.
- `widgets/ai_key_sheet.dart`: agregar una cuenta / cambiar la clave. **La clave se prueba antes
  de guardarla pidiendo la lista de modelos** (no gasta cuota de respuestas); si no anda, se dice
  por qué y no se guarda. Trampa: el controlador del campo avisa también al mover el cursor; el
  error se borra solo si cambió el texto (`_lastKey`, con su prueba).
- `widgets/ai_account_switcher.dart`: `AiAccountSwitcher` —el menú desplegable— en la pantalla y
  (`dense`) en la barra del chat; `aiAccountsViewProvider`, `AiAccountAvatar` (inicial con un color
  estable por cuenta). Elegir a mano vale desde el próximo pedido y dice «Ahora con …».
- `widgets/ai_notice_listener.dart`: `AiNoticeListener` en `app.dart` (sobre
  `GlobalErrorListener`): un aviso flotante con ícono y color por tipo para cada `AiNotice`, con
  «Cuentas» cuando sirve; el mismo aviso no se repite en 20 s (`kAiNoticeRepeatWindow`).
- `ai_model_texts.dart`: nombres, motivos de falla, la hora de renovación y los tokens cortos.
- `AiAccountActions` (`ai_models_providers.dart`): `add` (la primera cuenta queda elegida),
  `test` (si anda, le saca la marca de clave rechazada pero no la de cuota), `replaceKey` (la
  prueba antes y olvida las marcas de la vieja), `rename`, `remove` (olvida lo gastado y deja de
  estar elegida), `refreshModels`.
- Ajustes › IA › «Modelo de lenguaje» lleva a la pantalla nueva, con el proveedor de subtítulo; el
  ícono del chat también. 109 textos nuevos `lm*`/`notice*` (es y en).
- Pruebas: `language_model_screen_test.dart` (8) y 4 más de las acciones. Mutaciones: 18/18
  muertas (la del foco sobrevivió primero y se le agregó su prueba). Trampa de las pruebas:
  `enterText` no redibuja; hay que hacer `pump()` antes de tocar un botón que se habilita con el
  texto.

### Paso 4c — las pantallas preguntan qué le falta al modelo elegido (hecho)

Antes, con Gemini elegido, los botones de la IA seguían preguntando si Gemma estaba bajado
(`chatModelManagerProvider.isReady()`) y ofrecían bajarlo. Ahora todas preguntan
`languageModelStatusCheckProvider` y dicen lo que de verdad falta.

- `lib/features/ai_models/presentation/language_model_missing.dart` (nuevo):
  `languageModelMissingMessage` (Gemma sin bajar → el texto propio de cada pantalla si lo hay;
  sin clave → «es gratis y lleva un minuto» **solo** si el proveedor tiene capa gratis; claves
  rechazadas → «Ninguna clave anda», no la cuota; sin cuota → hasta cuándo, sin inventar una hora
  si no se sabe), `languageModelMissingAction` (`({label, route})`: bajar → `chatModel`; clave o
  cuota → `languageModel`), `showLanguageModelMissing` (el aviso con su botón),
  `ensureLanguageModelReady(context, ref, {downloadMessage, downloadLabel})` (lo usan los botones
  antes de pedir) y `LanguageModelMissingBanner` (dentro de una hoja: el botón cierra la hoja antes
  de ir).
- Lo usan: `summarize_button.dart`, `generate_quiz_button.dart`,
  `generate_derived_note_button.dart` (`ensureLanguageModelReady`); `ai_flashcards_sheet.dart` y
  `fill_notebook_sheet.dart` (`LanguageModelMissingBanner`; se fue `languageModelReadyProvider`
  de `ai_flashcards_providers.dart`); `ai_suggest_relations_dialog.dart`,
  `notebook_providers.dart`, `ai_notebook_controller.dart`,
  `notebook_suggestions_controller.dart` (el chequeo).
- `AskVaultQuestionUseCase` recibe `modelReady: Future<bool> Function()` en vez del administrador
  de Gemma: sin modelo, sigue mostrando las fuentes sin redactar.
- Chat (`chat_screen.dart`): guarda el `LanguageModelStatus` (no un `bool`), **escucha
  `languageModelStatusProvider`** —cargar una clave, cambiar de cuenta o quedarse sin cuota cambia
  el aviso sin salir del chat— y el aviso de arriba dice lo que falta, con «Mientras, las
  respuestas muestran las fuentes sin redactar» en el modo con la bóveda; su botón lleva a donde
  se resuelve (`_openModelScreen(route)`). Solo al pasar de no listo a listo se precarga el modelo.
- «Organizar con la IA» (`ai_organize_now.dart`): pregunta con `background: true` —lo hace la IA
  de fondo, con su tope del día— y dice «Falta cargar una clave…» o «La IA espera que vuelva su
  cuota…» además de los de siempre (pausa, falta bajar un modelo, en un momento). El modelo de
  búsqueda sigue haciendo falta igual que antes.
- 17 textos nuevos (es y en): `aiOrganizeNow/Many{NeedsKey,Waits}`, `chatSourcesMeanwhile` y
  los `aiStatus*` que usa el paso siguiente (el estado de la cola en Repasar y en Ajustes).
- Pruebas: `language_model_missing_test.dart` (10), 5 nuevas en `source_panel_test.dart`
  (organizar con la nube) y 1 en `chat_screen_test.dart`. Mutaciones: 17/17 muertas (la de «el
  botón de la hoja no la cierra» sobrevivió primero: la hoja quedaba abierta *debajo* de la
  pantalla nueva, fuera de escena, y `find.byType` no mira ahí; ahora se busca con
  `skipOffstage: false`).
  Trampa: **no correr pruebas mientras `tool/mutar.py` trabaja en segundo plano**: cambia los
  archivos de verdad y una prueba que corre a la vez falla por la mutación, no por el código.

### Lo que sigue

4. Falta: la cola de la IA de fondo con el estado nuevo —preguntar con `background: true`,
   `AiOrganizeWaitingForModel` con el motivo (`AiModelWait`) y un temporizador para retomar; un
   error de cuota, clave o red **pausa sin saltear** el elemento (las tarjetas pedidas vuelven al
   frente)— y sus vistas (`ai_queue_status.dart`, `review_empty_state.dart`, con los `aiStatus*`
   ya cargados); las partes por la ventana del modelo (`kFlashcardPartChars`,
   `kDerivedNotePartChars`, hoy 3.000 fijos).
5. `OpenAiBackend` y `AnthropicBackend`.
6. Pruebas con respuestas grabadas (nunca llamadas reales), mutación, guía, decisión 74.
