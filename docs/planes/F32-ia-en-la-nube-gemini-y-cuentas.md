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

### Paso 4d — la IA de fondo espera a la nube sin perder nada (hecho)

**La causa de fondo**: la cola de la IA atrapaba el error de cada paso, lo registraba y seguía; al
final cerraba la pasada. Con Gemma eso alcanzaba (un error era de ese pedido). Con la nube, un
error de cuota o de red a mitad de un elemento hacía que la pasada se cerrara **sin** los pasos que
faltaban, el elemento quedaba como organizado y no se volvía a tomar. Y como la cola tampoco
preguntaba si la nube podía contestar antes de tomar un elemento, cada intento gastaba uno de los
tres que tiene (`kMaxAiRunAttempts`).

- `AiOrganizeQueue` recibe `languageModel: () => LanguageModelStatusCheck` (antes `chatModel`, el
  administrador de Gemma) y `modelRetryDelay` (`kAiModelRetryDelay`, 5 minutos).
  - **Antes de tomar nada** pregunta con `background: true` —es la IA de fondo, con su tope del
    día—. Si falta Gemma o una cuenta → `AiOrganizeModelMissing` (con `keyFor`: el proveedor al que
    le falta la clave). Si no hay cuota, se llegó al tope o las claves no andan →
    `AiOrganizeWaitingForModel(reason, pending, resumesAt, cap)` y un temporizador que la despierta
    a esa hora (`_wakeAt`, con un segundo de margen).
  - `aiModelWaitFor(error)` dice qué errores de la nube son «esperar» y cuáles son de ese pedido:
    cuota → `quota`; tope → `backgroundCap`; clave inválida, prohibida o sin cuenta →
    `keysRejected`; red → `offline`; saturado o tope por minuto → `busy`; el modelo no existe →
    `modelGone`; bloqueado, demasiado largo o desconocido → `null` (se registra y se sigue como
    siempre). Un error que no es `CloudModelException` (Gemma) también da `null`.
  - **Un error de «esperar» a mitad de un elemento** corta ahí: `_hold` guarda la espera (hasta
    `retryAfter` o 5 minutos; `modelGone`, hasta que cambie lo elegido) y `_interrupted` guarda el
    elemento, su pasada **abierta** y los pasos ya hechos. Al volver, ese elemento va primero, en
    la **misma pasada**, sin repetir los pasos hechos. La espera existe aparte del chequeo porque
    el chequeo no ve la red ni un modelo que desapareció: sin ella, la cola giraría sobre el mismo
    error.
  - Las tarjetas pedidas (F30) igual: el elemento cortado no cuenta como mirado (`_cardDone` no
    corre), el aviso deja de decir qué lee, y al retomar sigue en su pasada con su `anotherBatch`.
    Cancelar el pedido cierra la pasada cortada con lo que alcanzó a hacer.
  - Pedir de nuevo el elemento cortado (organizar ya o tarjetas) no lo duplica; `_pending` lo
    cuenta entre los que esperan (los que vienen de la base ya los cuenta ella mientras su pasada
    esté abierta).
  - `languageModelChanged()` suelta la espera y la despierta. Lo llaman los proveedores al cambiar
    `aiModelSettingsProvider` (proveedor, cuenta, modelo) y `aiAccountsProvider` (cargar o borrar
    una clave).
- `languageModelNameProvider` (`chat_providers.dart`): el nombre del modelo que escribe —el de la
  nube elegido, o el recomendado, o el de Gemma—. Lo anotan las pasadas y las notas mapa.
- Vistas: `AiQueueWaitingView` (`ai_queue_status.dart`) con `reasonText` (hasta cuándo, con
  `aiResetTime`), `needsYou` (claves o modelo: color de atención) y `showsAccounts` (no sin
  conexión ni saturado: ahí no hay nada que ver). La tarjeta dice el motivo + «N elementos
  esperan; nada se pierde» y ofrece «Cuentas y cuota»; sin clave dice «Falta cargar una clave de
  Gemini…» con «Cargar una clave» (no «Bajar»). Repasar vacío (`review_empty_state.dart`) y el
  ajuste «Lo que hizo la IA» (`ai_settings_tiles.dart`) muestran lo mismo.
- Pruebas: 15 nuevas en `ai_organize_queue_test.dart` (grupo «con el modelo en la nube (F32)»),
  6 en `ai_activity_screen_test.dart`, 2 en `review_ai_flashcards_test.dart` y
  `ai_organize_queue_providers_test.dart` (nuevo: cargar una cuenta o elegir otro proveedor
  destraba la cola sola). `test/support/gemma_status_check.dart` arma el chequeo con Gemma para
  las pruebas que arman la cola a mano.
  Trampa: en `testWidgets`, `tester.pump()` **sin duración** no avanza el reloj falso; el refresco
  que agenda Riverpod es un timer en cero y solo corre con `tester.pump(Duration.zero)`.
- Mutaciones: 38/38 muertas. Dos sobrevivieron primero: pedir de nuevo las tarjetas del elemento
  cortado (no había prueba: se agregó) y el texto del botón de las cuentas en Repasar vacío, que
  repetía la condición de su acción (`_Reason` muestra el botón solo con las dos): se sacó la
  condición repetida.
- **`tool/mutar.py` se colgaba** con una mutación que hace girar la cola sin soltar el hilo (ni el
  `--timeout` de `flutter test` vence): con `shell=True`, al vencer su tiempo mataba solo la
  consola, y `dart`/`flutter_tester` seguían reteniendo la salida. Ahora la salida va a un archivo,
  al vencer mata el árbol entero (`taskkill /T`), cuenta la mutación como muerta («las pruebas se
  colgaron»), acepta `"minutos"` por mutación (10 si no está) e imprime cada resultado apenas lo
  tiene.

### Paso 4e — las partes de los textos largos según la ventana del modelo (hecho)

- `lib/features/ai_models/domain/services/model_text_budget.dart`: `ModelTextBudget(partChars,
  maxDraftsPerCall)` y `textBudgetFor(contextTokens)`. Una ventana de menos de
  `kLargeWindowTokens` (16.000) se reparte como Gemma (`kSmallWindowTextBudget`: 3.000
  caracteres y 4 tarjetas, lo medido en F27/F30). Una grande: la parte usa **un cuarto de la
  ventana** (a 3,5 caracteres por token) con tope **`kMaxPartChars` = 60.000** (un capítulo
  largo, ~17.000 tokens) y se piden **8 tarjetas** por pedido (`kLargeWindowDraftsPerCall`).
  **Por qué un tope y no el libro entero**: de una vez gastaría el tope por minuto de la capa
  gratuita, y en un libro dejaría menos partes de donde salen las tarjetas.
- `languageModelTextBudgetProvider` (`chat_providers.dart`): `ModelTextBudget Function()` con la
  ventana de `modelBackendProvider` (`contextTokens`: Gemma 2048; la nube, la del modelo elegido
  según su lista, o 128.000). **Se lee al usarlo**: cambiar de modelo vale desde el próximo
  elemento.
- Lo usan, **como parámetro obligatorio** (olvidarlo no compila, para que la nube nunca lea de a
  3.000 caracteres sin que nadie lo note): `generateFlashcardsByParts(budget:)` —se fueron
  `kFlashcardPartChars` y `kMaxFlashcardsPerCall`—, `AutoFlashcardsStep(textBudget:)` (se
  pregunta en cada elemento), las tarjetas a mano (`flashcard_section.dart`) y
  `GenerateDerivedNoteUseCase(textBudget:)` → `packDerivedSources(partChars:)` (se fue
  `kDerivedNotePartChars`; con la nube un cuaderno suele ir en un solo pedido).
- **Error encontrado y arreglado de raíz**: los derivados (`generate_derived_note_button.dart`)
  y «Llenar» un cuaderno (`fill_notebook_sheet.dart`) anotaban como autor la opción de Gemma
  (`chatModelOptionNotifierProvider.name`) aunque escribiera Gemini. Ahora usan
  `languageModelNameProvider`. (La de `languageModelBackendStoreProvider` está bien: es la GPU o
  CPU de cada variante de Gemma.)
- Pruebas: `model_text_budget_test.dart` (4), `language_model_text_budget_provider_test.dart`
  (2: Gemma, Gemini y el cambio en el acto), 2 en `auto_flashcards_step_test.dart` (un libro de
  123.000 caracteres en 3 pedidos en vez de 6, con las mismas 12 tarjetas; el presupuesto se
  pregunta en cada elemento), 1 en `flashcard_section_test.dart`, 1 en
  `generate_derived_note_usecase_test.dart` (14 fuentes en un solo pedido), y el autor en
  `generate_derived_note_button_test.dart` y `fill_notebook_sheet_test.dart`.
  Mutaciones: 11/11 muertas. Dos conexiones no se mutan sin romper la compilación (las tarjetas a
  mano y el paso en la cola): las cubre el parámetro obligatorio y la prueba del proveedor.

### Paso 5 — OpenAI y Claude (hecho, 11/N)

Diseño verificado en la guía de la API de Claude y en la documentación de OpenAI el 16/10/2026;
las pruebas, con respuestas grabadas, nunca llamadas reales.

- **`cloud_http.dart`**: `cloudOptions`, `sendCloudRequest`, `decodeCloudErrorBody`,
  `retryAfterOf` (la cabecera `retry-after` en segundos, con decimales). `GeminiWire` pasó a
  usarlo (se fueron sus `_send`/`_decodeError`, que eran lo mismo).
- **`AnthropicWire`** (`anthropic_wire.dart`): `POST https://api.anthropic.com/v1/messages`,
  cabeceras `x-api-key` y `anthropic-version: 2023-06-01`; cuerpo `model`, `max_tokens` (+2048
  de margen en los 5.x, que siempre piensan: `isFifthGeneration`), `system`, `messages`
  (`user`/`assistant`, fotos como bloque `image` base64 antes del texto), `stream: true`; en los
  5.x `output_config: {effort: "low"}`; **sin** `thinking` (en Opus 5.5 apagarlo es un 400). En
  `fallbackModels` (`claude-fable-5-1`, `claude-opus-5-5`, `claude-opus-5`, `claude-sonnet-5-5`):
  `fallbacks: "default"` y `anthropic-beta: server-side-fallback-2026-07-01` (en Haiku 5.5 y los
  4.x sería un 400); el bloque `fallback` llega como un `content_block_start` cualquiera y el
  texto sigue. Eventos: `message_start` (tokens de entrada), `text_delta` (lo pensado y la firma
  se saltean), `message_delta` (`stop_reason` y tokens de salida), `error` (se traduce por su
  tipo). `refusal` → `blocked` **aunque haya escrito algo** (lo escrito no vale como respuesta);
  `max_tokens` → cortada. Errores, por estado o por tipo: 402/`billing_error`/«credit balance» →
  `quotaExhausted`; 429 → `rateLimited` con `retry-after`; 401 `invalidKey`; 403 `forbidden`; 404
  `modelNotFound`; 413/«prompt is too long» `tooLong`; 5xx/529/`overloaded_error` `unavailable`.
  Modelos: `GET /v1/models?limit=1000`, con `after_id` = `last_id` mientras `has_more`; trae
  `max_input_tokens` (la ventana, que usa `textBudgetFor`) y `max_tokens`. Recomendado:
  `claude-opus-5-5`; si no está, el Opus más nuevo; si no, el primero.
- **`OpenAiWire`** (`openai_wire.dart`): Chat Completions (no «Responses», que guarda por
  defecto). `Authorization: Bearer`; `developer` en los que razonan (`reasons`: `o\d…`, GPT-5 en
  adelante salvo `-chat`), `system` en los demás; fotos como `image_url` con data URL;
  `max_completion_tokens` (+2048 en los que razonan); `reasoning_effort: "low"` solo en esos;
  `stream_options.include_usage`. `[DONE]` cierra; un `error` dentro del flujo se traduce.
  `length` → cortada; `content_filter` o `refusal` sin texto → `blocked`. Errores: **el código
  antes que el estado** (un 429 sin saldo no se arregla esperando). Modelos: `GET /v1/models`,
  solo `gpt-…` y `o\d…` de texto (`isTextModel`: fuera voz, tiempo real, imágenes, búsqueda,
  vectores, moderación, `-pro`, codex, deep-research, computer-use, instruct y las versiones con
  fecha); el nombre, como lo escribe OpenAI («GPT-5.2 mini»). Recomendado: el `gpt-N(.M)` más
  nuevo sin sufijo.
- **Error encontrado y arreglado de raíz**: el recomendado comparaba versiones como número
  decimal, y «gemini-3.10» quedaba por debajo de «3.9». Ahora son enteros (mayor, menor), en
  los tres formatos.
- `cloudWiresProvider` tiene los tres: OpenAI y Claude aparecen en «Modelo de lenguaje». El
  aviso de privacidad de pago ahora dice además que el proveedor puede guardar lo mandado unas
  semanas para controlar abusos. La tarjeta de OpenAI dice «Los modelos GPT» (ChatGPT es la app).
- Pruebas: `anthropic_wire_test.dart` (17), `openai_wire_test.dart` (17), el servidor de mentira
  compartido `test/support/fake_cloud_server.dart` (con cabeceras, para `retry-after`), 1 en
  `gemini_wire_test.dart` (3.10 > 3.9), 1 en `ai_models_providers_test.dart` (la app real tiene
  los tres formatos) y 1 en `language_model_screen_test.dart` (elegir Claude pide el aviso de
  pago y su clave). Mutaciones: 47/47 muertas.

### Lo que sigue

5. La suite entera, y la limpieza final con el espacio en disco medido antes y después.
6. La prueba en el teléfono con una clave real, solo si el usuario la pide.
7. Después, F33 (`docs/planes/F33-revisar-con-otro-modelo.md`, aprobada).
