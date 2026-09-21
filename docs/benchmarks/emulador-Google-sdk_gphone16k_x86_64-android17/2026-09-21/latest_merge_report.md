# Fusión a escala (F11)

Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM

- dos copias de la bóveda de 10000 elementos (683 MB cada una): 1766 ms
- lo que edita tel: 11750 ms
- lo que edita pc: 3008 ms
- **fusionar la copia de tel en pc: 19770 ms** (VaultMergeResult(itemsAdded: 250, itemsUpdated: 475, fieldsUpdated: 475, conflictsRecorded: 75, spacesAdded: 0, renditionsAdded: 270, textsUpdated: 0, relationsAdded: 300, highlightsAdded: 0, flashcardsAdded: 100, flashcardsUpdated: 0, reviewsAdded: 0, provenancesAdded: 0, conversationsAdded: 0, messagesAdded: 0, propertyDefinitionsAdded: 0, propertyValuesAdded: 0, propertyAliasesAdded: 0, propertyAssignmentsAdded: 0, sourcesChunked: 200, sourcesPending: 0, filesCopied: 0, filesCopiedBytes: 0, filesMissing: 0, filesDiffering: 0))
- `verifyChunkInvariant` de pc, entera: 7500 fuentes con texto, 323217 chunks, 0 fuentes sin texto: invariante OK (2181 ms)
- fusionar lo mismo otra vez: 11001 ms (VaultMergeResult(itemsAdded: 0, itemsUpdated: 0, fieldsUpdated: 0, conflictsRecorded: 0, spacesAdded: 0, renditionsAdded: 0, textsUpdated: 0, relationsAdded: 0, highlightsAdded: 0, flashcardsAdded: 0, flashcardsUpdated: 0, reviewsAdded: 0, provenancesAdded: 0, conversationsAdded: 0, messagesAdded: 0, propertyDefinitionsAdded: 0, propertyValuesAdded: 0, propertyAliasesAdded: 0, propertyAssignmentsAdded: 0, sourcesChunked: 0, sourcesPending: 0, filesCopied: 0, filesCopiedBytes: 0, filesMissing: 0, filesDiffering: 0))
- **la copia de tel en una bóveda vacía: 68185 ms** (VaultMergeResult(itemsAdded: 10250, itemsUpdated: 0, fieldsUpdated: 0, conflictsRecorded: 0, spacesAdded: 12, renditionsAdded: 10250, textsUpdated: 0, relationsAdded: 25300, highlightsAdded: 4316, flashcardsAdded: 3057, flashcardsUpdated: 0, reviewsAdded: 0, provenancesAdded: 0, conversationsAdded: 0, messagesAdded: 0, propertyDefinitionsAdded: 10, propertyValuesAdded: 3427, propertyAliasesAdded: 0, propertyAssignmentsAdded: 37252, sourcesChunked: 7400, sourcesPending: 0, filesCopied: 0, filesCopiedBytes: 0, filesMissing: 0, filesDiffering: 0))
- vínculos: 25300 en la copia, 28994 en la bóveda vacía (los `[[ ]]` de las notas, ya resueltos)
- `verifyChunkInvariant` de la bóveda vacía, entera: 7400 fuentes con texto, 320229 chunks, 0 fuentes sin texto: invariante OK (2166 ms)
