# Piano per Terra: commenti e decisioni umane sugli artefatti di Story Start

Data: 10 settembre 2026. Stato: piano di implementazione, non funzionalità già realizzata.

## 1. Obiettivo e perimetro

Permettere di leggere in Familiar gli artefatti prodotti da `story-start`, commentare documenti e sezioni, rispondere ai punti aperti e registrare decisioni esplicite che Mana possa recepire nel workflow successivo. I contributi devono sopravvivere a navigazione, riapertura, refresh, rigenerazioni e utilizzo prolungato, senza confondere commenti, decisioni e approvazioni.

Implementare il percorso completo nei due repository:

- Familiar: `/Users/zel/projects/mana-familiar`, interfaccia, client tipizzati, bozze locali, navigazione e test UI.
- Mana: `/Users/zel/projects/mana`, contratti, persistenza, validazione, proiezioni inspect e consumo dei contributi in Story Start.

La richiesta autorizza una futura implementazione di questo perimetro, comprese le necessarie evoluzioni dei contratti nei due progetti. Questo documento non avvia implementazioni né altri agenti. Terra deve leggere le istruzioni applicabili e lo stato Git di entrambi i repository, preservando modifiche preesistenti. Eventuali limiti di scrittura del proprio ambiente vanno gestiti tramite le normali autorizzazioni dell'ambiente, senza aggirarli.

Il confine attuale di sola lettura è una scelta di prodotto da aggiornare esplicitamente: Familiar presenterà azioni umane, Mana resterà proprietario di scritture e semantica. Non fermarsi alla sola UI o a un salvataggio che i flussi successivi ignorano.

### Incluso nella prima release

- Commenti Markdown a documento/sezione, risposte e risoluzione/riapertura del thread.
- Risposte a domande con identità strutturata quando il producer le espone.
- Registrazione di decisioni su alternative strutturate esistenti, con motivazione e autore dichiarato; cronologia delle sostituzioni.
- Lettura dei contributi da inspect e consumo verificato da Story Start.
- Bozze locali recuperabili, conflitti espliciti, gestione di retry e riavvii.
- Test puntuali, integrazione fra repository, E2E desktop e sessioni lunghe.

### Rinviato

- Modifica libera e sovrascrittura dei Markdown generati; editor visuale stile Word.
- Commenti su intervalli arbitrari di caratteri, editing simultaneo in tempo reale, sincronizzazione cloud.
- Approvazione di review, merge, espansione automatica dello scope e avvio automatico di modelli dal pulsante Salva.
- I miglioramenti generali dell'audit UI precedente, salvo correzioni indispensabili ai flussi qui descritti.

L'editor Markdown richiesto in questa fase è quello dei contributi umani. La modifica libera dei documenti potrà usare in seguito lo stesso componente, soltanto con capability esplicita del producer e un contratto separato.

## 2. Baseline e punti di integrazione verificati

Familiar:

- [Confine di prodotto](product-boundary.md) e [architettura](architecture.md): niente scritture o reinterpretazione dei record Mana nel client.
- [Reader](../lib/presentation/artifact_detail_view.dart): `MarkdownNoteView` ha Reader/Source/Metadata, selezione e indice delle sezioni.
- [Editor esistente](../lib/presentation/read_only_source_editor.dart): `re_editor` è già una dipendenza, oggi usata in sola lettura. Valutarne il riuso per il composer; non rendere scrivibile il source viewer esistente.
- [Trasporto e repository](../lib/application/mana_inspect.dart): negoziazione inspect, timeout, dati precedenti conservati e cache dei dossier. La revisione usata per un salvataggio deve essere un token del producer, non un contatore UI o il timestamp del watcher.
- [Observatory](../lib/presentation/project_observatory_page.dart), [route](../lib/application/semantic_navigation.dart), [watcher](../lib/application/mana_workspace_watcher.dart).
- [Test document workspace](../test/f17_document_workspace_test.dart), [dossier](../test/work_item_dossier_test.dart), [resilienza](../test/project_observatory_resilience_test.dart), [prestazioni](../test/performance_regression_test.dart).
- [C02](../tests/run-c02-semantic-observatory-harness.sh) verifica inspect reale e assenza di scritture nel progetto; non allentare questa garanzia.
- [Catture UX](agentic-ux-testing.md): widget sintetici, non E2E desktop. Il valutatore agentico resta facoltativo e informativo.

Mana, percorsi relativi al suo repository:

- `docs/workflow/story-start-scope-v2.md`, `contracts/story-start/scope-v2/SEMANTIC-CONTRACT.md` e `schemas/common.schema.json`, `decision-register.schema.json`, `planning-context.schema.json`.
- `scripts/lib/story-start-scope-v2.sh`, `story-start-scope-v2-normalize.py`, `story-start-scope-v2-render.py`: pipeline, contesto e report deterministico.
- `scripts/mana-inspect.sh`, `scripts/validate-inspect-contract.sh`, `scripts/verify-inspect-consumer-compatibility.sh`.
- `tests/story-start-scope-v2-integration.sh`, `story-start-scope-v2-governor.sh`, `story-start-scope-v2-release-gate.sh` e relative fixture.
- `scripts/mana-workspace.sh` crea già `decisions/decision-log.md` e `decisions/developer-choice-log.md`; `scripts/mana-user-learning.sh` legge scelte confermate. Verificare questi consumatori prima di introdurre una seconda rappresentazione delle scelte.

V2 è attualmente opt-in e pubblica un report Markdown derivato da JSON; v1 resta il percorso predefinito. Il marker `validation/story-start-scope-run-v2.json` è pubblicato per ultimo. Commentare un report non equivale a modificare `selectedOptionId` o a validare un piano. Conservare queste distinzioni.

Baseline della sessione: `flutter analyze --no-pub` pulito; 175 test passati, 4 integrazioni saltate perché richiedono harness; otto catture sintetiche riuscite. Sono osservazioni precedenti all'implementazione, non criteri numerici da conservare artificialmente.

## 3. Contratto da definire prima della UI

Scrivere una breve ADR e fixture request/response versionate. I nomi seguenti descrivono operazioni proposte, non API già esistenti: Terra deve scegliere nomi coerenti con il CLI Mana e documentare gli effettivi comandi nella consegna.

### Identità e dati

Ogni contributo identifica progetto, workspace/work item, artefatto e versione sorgente. Per una sezione usare un riferimento emesso/validato dal producer, non uno slug inventato dal reader. Per domande e decisioni utilizzare l'ID strutturato del producer. Il solo percorso o titolo non garantisce identità tra rigenerazioni.

Definire almeno:

| Entità | Campi e comportamento richiesti |
| --- | --- |
| Thread | ID stabile, target, revisione sorgente, riferimento sezione opzionale, stato aperto/risolto, revisione concorrente |
| Contributo | ID, thread, tipo commento/risposta, corpo Markdown, autore dichiarato, timestamp del producer, collegamento alla versione precedente se corretto |
| Decisione umana | Decision ID, option ID valido, motivazione, autore, evidenza umana, revisione attesa, eventuale decisione sostituita |
| Collegamento | Stato valido / versione cambiata da verificare / target assente / riferimento ambiguo; nessun riaggancio silenzioso |
| Risultato comando | Operation ID, esito tipizzato, revisioni risultanti, riferimenti persistiti, stato dell'eventuale aggiornamento delle proiezioni |
| Capability | Operazioni e versioni supportate; possibilità effettiva per quel target; assenza distinta da errore di lettura |

L'autore locale è dichiarato, non autenticato: riusare un'identità configurata con origine esplicita o richiederla al primo contributo. Non inventare un'identità verificata da username o Git. Non introdurre un sistema di account in questa fase.

Commento, risposta, risoluzione del thread, decisione e approvazione sono azioni diverse. Una risposta libera non chiude automaticamente una decisione, e risolvere un thread non cambia lifecycle/review. La modifica di una decisione registra un evento successivo; non cancella la storia.

### Operazioni, compatibilità e concorrenza

- Esporre lettura paginata dei thread/contributi e azioni separate per commentare, rispondere, risolvere/riaprire, registrare/sostituire decisioni e verificare l'esito di un comando.
- Mantenere `inspect` senza scritture. Negoziare le nuove letture e le capability di scrittura senza cambiare il significato degli otto contratti inspect v1; versionare le modifiche incompatibili.
- Familiar passa identità e payload strutturati a Mana con argomenti separati e body JSON via stdin o meccanismo equivalente del progetto. Niente interpolazione shell del Markdown e niente scritture dirette nei record `.mana`.
- Revisioni distinte per versione dell'artefatto, thread e registro decisioni evitano conflitti inutili tra documenti indipendenti. Una decisione richiede anche la revisione delle alternative su cui l'utente ha scelto.
- Ogni mutazione ha una chiave di idempotenza persistente, vincolata a progetto e digest della richiesta. Stessa chiave/stesso contenuto restituisce lo stesso risultato; stessa chiave/contenuto diverso è errore. Doppio click, retry e riavvio non duplicano eventi.
- Usare confronto della revisione e scrittura sotto un unico confine di concorrenza: controllo seguito da scrittura non protetta non basta. Due processi sulla stessa revisione devono avere un esito determinato, mai perdita silenziosa dell'aggiornamento.
- In caso di timeout, la scrittura può essere già avvenuta: stato UI «esito da verificare», riconciliazione tramite operation ID e retry idempotente. Non dichiarare fallimento definitivo o successo senza evidenza.
- Storage dei contributi sotto proprietà Mana, separato dagli output generati. Preferire un registro canonico con scritture atomiche recuperabili e proiezioni ricostruibili; definire lock, recupero dopo crash, limiti, compatibilità Windows e retention dei risultati idempotenti.
- Se registro e proiezioni richiedono più file, documentare il commit point. Un crash intermedio deve produrre uno stato recuperabile e dichiarato; una serie di rename non è da sola una transazione multi-file.
- Validare dimensioni, schemi, target, appartenenza al progetto, symlink e path containment nel producer. I limiti di body, pagina e cache devono essere espliciti e verificati ai confini.
- Producer vecchio, snapshot e artefatto offline: lettura esistente preservata, azioni indisponibili con motivazione; nessun fallback di scrittura su file ricavato dalla preview.

## 4. Collegamento con Story Start e rigenerazioni

Implementare questa parte in Mana prima di dichiarare complete le decisioni in Familiar.

1. Esporre tramite inspect i target commentabili, le domande, le decisioni e le alternative realmente disponibili. Per i Markdown legacy consentire commenti a documento/sezione; non ricostruire decisioni strutturate analizzando frasi nella UI.
2. Salvare un commento senza modificare i byte degli output generati. Presentarlo nel reader come contributo umano distinto e renderlo disponibile al successivo contesto Story Start con provenienza.
3. Una decisione valida registra scelta e motivazione come evidenza umana. Validare che l'opzione appartenga a quella decisione e che stato/revisione consentano l'azione. L'azione non costituisce un'approvazione generale o un'autorizzazione all'espansione dello scope.
4. Rendere espliciti «decisione registrata» e «piano aggiornato». Se la proiezione è calcolabile deterministicamente, rigenerarla passando il governor; se serve una nuova pianificazione, pubblicare «ripianificazione necessaria». Non inventare nuove stime né avviare un provider dal salvataggio.
5. Al successivo Story Start includere commenti/risposte come input umano con origine e stato; applicare le decisioni compatibili come vincoli verificabili. Il contesto bounded non deve troncare silenziosamente decisioni applicabili: paginare o fallire con diagnostica quando non possono essere incluse. Non riaprire una scelta confermata perché un provider l'ha omessa.
6. Verificare governor, rami mutuamente esclusivi, stime, riferimenti e review. Una scelta risolta non rende automaticamente il piano approvato né libera una stima finale finché rimangono decisioni materiali aperte o validazione mancante.
7. Se il target scompare, cambia significato o ha alternative diverse, conservare il contributo originale e marcarlo da riconciliare. Stabilire la compatibilità nel producer tramite identità/provenienza; non basta l'uguaglianza del titolo o di un ID derivato dal contenuto.
8. Rigenerazioni concorrenti e salvataggi devono condividere controllo di revisione/pubblicazione. Inspect non deve presentare come coerente una combinazione di report, decisioni e piano appartenenti a pubblicazioni diverse.
9. Per v1, verificare il flusso di contesto e i choice log esistenti: i contributi devono arrivare al percorso successivo supportato con origine esplicita. Se manca una decisione strutturata, offrire commento/risposta, non un pulsante che promette una transizione inesistente. Documentare esattamente la matrice v1/v2.

I contributi persistono una sola volta nella fonte canonica. Eventuali choice log o report derivati devono dichiarare provenienza e non generare doppioni nei consumatori, inclusa la raccolta di learning.

## 5. UI, bozze e lifecycle desktop

### Reader e composer

- Aggiungere «Commenti» con conteggio e filtro aperti/tutti. Pannello affiancato su finestra ampia, vista dedicata o pannello sovrapposto sul compatto; il documento deve restare leggibile.
- «Commenta questa sezione» usa il target del producer. In assenza di mappatura affidabile proporre il commento al documento senza inventare un ancoraggio.
- Composer Markdown con anteprima inerte, Salva/Annulla, stato bozza, validazione e scorciatoia di salvataggio. Riutilizzare componenti esistenti senza rendere eseguibili HTML, link o codice nei contributi.
- Per una decisione mostrare domanda, alternative valide, motivazione e azione esplicita «Registra decisione». Non richiedere una seconda conferma generica dopo il click intenzionale; segnalare sostituzioni e conseguenze effettive prima dell'invio.
- Mostrare separatamente stato del contributo, collegamento al documento e aggiornamento del piano. Errori utili e recuperabili, senza perdere il testo.
- Il badge di conteggio e i thread devono distinguere zero risultati da caricamento, indisponibilità e capability assente.

### Bozze, richieste asincrone e navigazione

- Bozze persistite fuori dal progetto, nello storage applicativo, con namespace progetto/work item/artefatto/thread/composer. I test usano una directory temporanea esplicita, mai preferenze reali.
- Definire stati almeno: bozza, salvataggio locale in corso, salvata localmente, invio, esito da verificare, persistita in Mana, conflitto, errore recuperabile. Non confondere «salvata localmente» con «pubblicata».
- Debounce breve documentato per la bozza; flush su normale navigazione e chiusura. Un crash può perdere al massimo la finestra di debounce non ancora confermata; il testo dichiarato salvato localmente deve essere recuperabile. Testare entrambi i casi.
- Back/Forward, cambio scheda, progetto, documento, tema e refresh non cancellano la bozza. Annulla/scarta è un'azione esplicita; una bozza già pubblicata non deve ricomparire come da inviare.
- Persistenza della chiave idempotente prima dell'invio, così il riavvio dopo commit e prima dell'ACK riconcilia lo stesso comando.
- Namespace per finestra/sessione: due finestre possono avere bozze indipendenti sullo stesso documento senza sovrascriversi. La concorrenza delle pubblicazioni è risolta dal producer.
- Le risposte tardive aggiornano soltanto target e revisione corretti. Dopo cambio progetto o dispose non devono modificare il nuovo dossier o ricreare controller/watcher.
- Conflitto: preservare testo locale e mostrare stato remoto aggiornato, permettendo revisione/reinvio esplicito. Niente last-write-wins e niente merge automatico di scelte decisionali.
- Dopo mutazione confermata invalidare solo letture pertinenti e riconciliare dossier, commenti, decisioni e activity. Debounce/coalescing degli eventi del watcher, senza refresh infinito generato dalla propria scrittura.
- Liste paginate/lazy, cache e registri di richieste bounded; le bozze attive non vengono espulse come cache. Definire conservazione delle bozze recuperate ed eliminazione esplicita senza cancellazione silenziosa per quota.
- Verificare chiusura finestra e Quit nativi su macOS/Windows; un solo test di dispose Flutter non prova il flush in chiusura reale.

### Organizzazione del codice proposta

Creare moduli dedicati, con nomi definitivi a discrezione di Terra: client delle mutazioni, repository dei contributi, archivio bozze, controller del composer, pannello commenti e form decisione. Non aggiungere tutto alla pagina Observatory già molto grande. Riutilizzare route, renderer sicuro e trasporto dove appropriato mantenendo distinto il canale di lettura da quello di scrittura.

## 6. Test puntuali obbligatori

Usare test deterministici con clock, transport e storage iniettati; verificare risultati osservabili e persistenza, non soltanto chiamate a mock o snapshot di widget.

| Area | Casi richiesti e oracle |
| --- | --- |
| Contratto | Schemi validi/incompatibili, capability assente, campi additivi, campi obbligatori mancanti; vecchi client continuano a leggere |
| Testo | Italiano, emoji, Unicode composto, multilinea, tabelle, backtick, `$()`, CRLF/LF; roundtrip del body senza trasformazioni inattese |
| Limiti e input ostile | Body/pagina al limite e oltre, ID estranei, traversal, symlink sostituito, file target assente, Markdown/HTML inerte; nessuna esecuzione o scrittura esterna |
| Thread | Creazione, risposta, risoluzione, riapertura, correzione con storia; nessuna modifica implicita di lifecycle/review |
| Decisioni | Opzione valida, estranea, rimossa, revisione vecchia, decisione già risolta, sostituzione; evidenza umana e governor coerenti |
| Idempotenza | Doppio click, stesso payload dopo riavvio, commit seguito da timeout, chiave riusata con altro payload; esattamente un evento canonico |
| Concorrenza | Due processi sulla stessa revisione; una decisione accettata e un conflitto, nessuna perdita; target indipendenti non si bloccano inutilmente |
| Crash | Prima del commit, dopo commit/prima ACK, durante proiezione, lock interrotto; recupero senza record parziali né falso successo |
| Bozze | Debounce, flush, riapertura, testo scartato, record corrotto, quota, due finestre; nessuna perdita del testo dichiarato persistito |
| UI asincrona | Risposte fuori ordine, dispose durante invio, cambio progetto con richiesta attiva, refresh fallito e recuperato; identità sempre corretta |
| Rigenerazione | Stessa identità valida, contenuto cambiato, sezione rinominata, heading duplicati, target cancellato, alternative mutate; nessun riaggancio silenzioso |
| Letture | Paginazione senza buchi/doppioni, cursore invalidato da nuova revisione, cache invalidata dopo write; conteggi coerenti |
| Workflow | Commento non chiude decisione; scelta confermata entra nel contesto successivo; provider che la omette/contraddice non pubblica un piano apparentemente valido |
| Accessibilità | Tab/Shift-Tab, focus restituito al documento, salvataggio da tastiera, etichette screen reader, stati selezionati e annunci di errore/successo |

Possibili nuovi file Familiar: `test/human_feedback_client_test.dart`, `human_feedback_repository_test.dart`, `feedback_draft_store_test.dart`, `artifact_comments_test.dart`, `decision_form_test.dart`. Integrare inoltre dossier, document workspace, watcher, sicurezza e resilienza esistenti. I nomi sono proposti; mantenere la convenzione del repository.

## 7. E2E: evolvere i flussi esistenti senza perdere le garanzie

### C00/C01/C02 e test Mana esistenti

- Conservare C01/C02 e tutte le fasi inspect con `writes=false`, zero provider reali e confronto dello stato del progetto prima/dopo. La possibilità di scrivere non giustifica scritture durante lettura, navigazione o refresh.
- Estendere C02 con letture dei contributi di una fixture già preparata, capability nuove/assenti e fallback legacy; creare lo stato prima della finestra di verifica no-write.
- Estendere il compatibility gate producer/consumer ai nuovi contratti e alla matrice vecchio producer/nuovo client, nuovo producer/letture precedenti.
- Estendere in Mana integrazione, governor e release gate Story Start v2 per risposte/decisioni umane, riesecuzione e pubblicazione coerente. Riutilizzare il provider stub deterministico già presente; dimostrare che il contesto reale consegnato al planner contiene i contributi, non solo che una fixture finale li contiene.

### Nuovo C03: percorso di scrittura reale fra repository

Creare `tests/run-c03-human-feedback-harness.py` e il relativo test Flutter, oppure nomi equivalenti documentati. Preferire un orchestratore portabile per i nuovi scenari; non copiare dipendenze macOS come `stat -f` nel runner Windows. I comandi seguenti sono obiettivi da implementare, non comandi disponibili oggi.

Il runner deve creare progetti sintetici tramite bootstrap supportato, configurazione applicativa temporanea e due work item con titoli simili. Invocare il producer reale e montare il client/UI reali; stub soltanto dei provider di generazione e dell'iniezione esplicita dei guasti. Non definire E2E un test che sostituisce con mock il salvataggio Mana.

Scenari obbligatori:

1. **Lettura → commento → riapertura:** aprire documento, commentare una sezione, rispondere, risolvere/riaprire, tornare al dossier, chiudere e riaprire; confrontare testo, target, conteggi e storia via inspect e storage canonico.
2. **Punto aperto → decisione → nuova esecuzione:** risposta contestuale, scelta di alternativa valida e motivazione; rieseguire Story Start con provider stub. Verificare evidenza, contesto consegnato, ramo selezionato, report, governor e stato del piano. Ripetere con un'altra decisione materiale ancora aperta e stima finale ancora non disponibile.
3. **Bozza → navigazione → crash:** scrivere, cambiare documento/progetto, tornare; interrompere il processo dopo conferma di salvataggio locale, riavviare, recuperare, pubblicare. Verificare isolamento delle due storie.
4. **Due finestre:** entrambe leggono la stessa decisione, una sceglie A e l'altra B; la seconda vede conflitto e conserva la motivazione. Dopo rilettura può sostituire esplicitamente la scelta; storia completa e una sola scelta corrente.
5. **Rigenerazione con thread:** commentare, rigenerare mantenendo alcuni target e rinominandone/rimuovendone altri; preservare tutti i contributi e segnalare quelli da ricollegare. Verificare che un heading omonimo su un altro documento non riceva il thread.
6. **Commit con ACK perso:** il producer persiste, la risposta viene persa; UI incerta, riavvio, verifica operation ID, nessun doppione né seconda decisione.
7. **Errori e recupero:** permesso negato, storage pieno simulato, producer terminato, payload malformato, lock occupato, refresh fallito, capability ritirata; nessun falso successo e recupero del testo.
8. **Compatibilità e sola lettura:** snapshot, vecchio producer, v1 e v2; controlli coerenti con capability, nessuna scrittura da operazioni inspect.

Per ogni mutazione registrare l'insieme esatto dei file modificabili previsto dal caso. Non autorizzare genericamente tutta `.mana`: commenti scrivono solo registro/proiezioni dichiarate; aggiornamento del piano ha un diverso insieme ammesso. Confrontare hash dei sorgenti, report non coinvolti, manifest e sentinelle esterne; verificare anche Git index/HEAD invariati. Il setup delle fixture è distinto dalle scritture dell'azione sotto test.

### E2E desktop nativo

Aggiungere `integration_test/human_feedback_desktop_test.dart` e il driver/runner necessario. Coprire apertura UI, input reale, salvataggio, pannelli, focus, resize e chiusura/riavvio; usare un launcher esterno per kill/restart, perché un test nel processo terminato non può verificare autonomamente il riavvio. Due processi distinti devono esercitare davvero il controllo concorrente del producer.

Eseguire su macOS e Windows prima di dichiarare supportata la funzione su entrambi. Un test host-side Flutter con producer reale dimostra integrazione applicativa, non menu, dialoghi e lifecycle nativi: etichettare le evidenze separatamente. Se manca il runner Windows, riportare la verifica mancante e predisporre il job; non trasformarla in pass.

## 8. Stress e utilizzo prolungato

Usare due livelli: sequenze accelerate deterministiche per esplorare molte transizioni e sessioni desktop a tempo reale per timer, risorse e lifecycle. Un clock simulato o una pausa di venti minuti non dimostrano utilizzo prolungato.

### Profili riproducibili

| Profilo | Carico minimo | Esecuzione prevista |
| --- | --- | --- |
| Smoke | 3 seed fissi × 100 azioni, 2 progetti e 10 documenti | Ogni PR, insieme a C03 breve |
| Stress deterministico | 5 seed × 2.000 azioni, 100 documenti, 5.000 contributi preesistenti distribuiti e un thread da 1.000 risposte | Job dedicato/schedulato e prima della consegna |
| Sessione desktop lunga | 20 minuti reali di attività, almeno 300 azioni, 2 finestre, 5 rigenerazioni, 3 riavvii e 10 guasti recuperabili | Accettazione locale e job dedicato |
| Soak | 60 minuti reali, almeno 1.000 azioni e ripetizione di conflitti/rigenerazioni/restart | Job schedulato o manuale prima della release |

Le durate comprendono uso effettivo: alternare digitazione in più riprese, salvataggi, lettura, scroll, ricerca, cambio scheda/progetto, Back/Forward, risposte e recupero errori. Distribuire i guasti nel corso della sessione, inclusa la parte finale; non concentrarli tutti nell'avvio. Seed, schedule e conteggi sono fissati prima del run.

### Oracle e invarianti

- Il runner mantiene un modello atteso indipendente, costruito dalle azioni confermate e dai conflitti previsti. Non ottenere l'atteso deserializzando la stessa proiezione che si vuole validare.
- Dopo ogni mutazione e ogni checkpoint confrontare UI, inspect e registro canonico: ID, body, target, revisione, stato del thread, decisione corrente e cronologia.
- Esattamente un contributo per operation ID accettato; nessuna perdita di aggiornamenti confermati, contaminazione tra progetti o bozze sul target sbagliato.
- Le azioni rifiutate non cambiano il dominio. Le azioni con ACK perso sono riconciliate prima di assegnare l'esito finale.
- Le finestre di sola lettura non scrivono nel progetto. Nessun provider reale o accesso a progetti dell'utente.
- Nessun controller, listener, watcher o processo figlio superstite dopo chiusura. Contatori di test devono tornare al baseline; cache e pagine rispettano limiti espliciti.
- Misurare memoria, handle/processi, latenza input e salvataggio, frame e chiamate al producer. Campionare dopo warm-up e a fine blocchi equivalenti; non attribuire automaticamente alla UI la crescita del dataset.
- Definire nel runner soglie prima delle misure: input p95 ≤ 100 ms in profile mode sul runner dichiarato; p95 salvataggio nell'ultimo quarto ≤ 2× il primo quarto a carico confrontabile; numero di processi/orologi/listener stabile dopo teardown. Un limite assoluto di timeout deve comunque impedire hang.
- Per memoria confrontare blocchi con working set fisso, dopo warm-up e quiescenza: baseline, mediana di almeno tre campioni finali e soglia iniziale `max(30 MiB, 15% baseline)` per la crescita residua. Riportare RSS separatamente dalla memoria gestita; se il runner non consente una misura affidabile, segnare il gate non misurato e integrare lo strumento, non inventare un risultato.
- I limiti temporali hardware-dipendenti vanno legati a macchina/build e registrati. Se risultano inadatti, motivare la revisione prima di una nuova campagna mantenendo gli esiti precedenti; non alzarli a posteriori per promuovere il run.

Supportare replay di un seed e dell'action trace fallito. Conservare primo errore e report parziale; non rieseguire fino al verde cancellando le prove. Ogni nuovo tentativo ha directory e identificatore nuovi.

## 9. Verifica visiva e aggiornamento del percorso UX

Estendere lo scenario sintetico attuale conservando PAY-42 e i controlli già presenti. Aggiungere un percorso separato con documento → commento → risposta → decisione → conflitto → bozza recuperata → revisione rigenerata.

- Catture 1440×900 chiaro, 1024×768 scuro al 130% e 800×600 con testo al 200% per il composer e i controlli essenziali.
- Verificare contenuto realmente visibile/hit-testable, accessibilità delle azioni tramite scroll e assenza di sovrapposizioni della tastiera/focus; trovare un widget non prova leggibilità.
- Testare stringhe lunghe, alternative multilinea, molti thread, body esteso e pulsanti durante errore/conflitto.
- Catturare bozza locale, salvataggio confermato, esito incerto, conflitto, thread da ricollegare e decisione con piano ancora da aggiornare. Gli stati devono essere distinguibili senza affidarsi soltanto al colore.
- Aggiornare manifest/oracle del nuovo scenario con versione e test del runner, preservando i controlli precedenti. Ispezionare le PNG prodotte; non ritoccarle.
- Il percorso di cattura continua a funzionare senza modello. Non avviare un osservatore agentico come parte implicita della feature; eventuale valutazione separata resta informativa e non sostituisce gli oracle di persistenza/semantica.

## 10. Fasi di implementazione e criteri di uscita

| Fase | Consegna | Criterio di uscita |
| --- | --- | --- |
| F0 | ADR, matrice v1/v2, contratti e fixture, strategia transazionale | Request/response ed errori concreti; ownership e concorrenza definite, nessuna API inventata solo nel client |
| F1 | Storage e comandi Mana, letture inspect, idempotenza | Test contratti, crash, due processi e no-write passati |
| F2 | Integrazione Story Start e proiezioni | Decisione recepita dal contesto reale e validata dal governor; rigenerazione e compatibilità dimostrate |
| F3 | Client, bozze e UI Familiar | Commentare/rispondere/registrare decisioni con tutti gli stati; test puntuali e navigazione verdi |
| F4 | C03, regressioni C00/C01/C02 e desktop | Percorsi reali persistono correttamente, guasti e restart verificati, evidenze per piattaforma |
| F5 | Stress, sessione lunga, catture e documentazione | Tutti i minimi eseguiti, invarianti rispettate, report riproducibile senza buchi |

Non dichiarare completato l'obiettivo dopo F3. Il consumo successivo delle decisioni, i conflitti e le sessioni lunghe fanno parte della funzionalità richiesta.

### Comandi di verifica

Comandi esistenti Familiar, da eseguire nell'ambiente configurato:

```sh
flutter analyze --no-pub
flutter test --no-pub
python3 -B -m unittest discover -s tests -p 'test_*.py'
tests/run-c01-zero-token-harness.sh --mana-root /Users/zel/projects/mana
tests/run-c02-semantic-observatory-harness.sh --mana-root /Users/zel/projects/mana
git diff --check
```

Eseguire anche formatter in modalità check, build desktop per le piattaforme verificate e gate Mana pertinenti: `scripts/validate-inspect-contract.sh`, `scripts/verify-inspect-consumer-compatibility.sh --familiar-root /Users/zel/projects/mana-familiar`, `tests/story-start-scope-v2-integration.sh`, `tests/story-start-scope-v2-release-gate.sh`. Controllare eventuali prerequisiti nei runner; non sostituire uno skip con successo.

Interfaccia proposta del nuovo runner da implementare e documentare:

```sh
python3 tests/run-c03-human-feedback-harness.py --mana-root /Users/zel/projects/mana --profile smoke
python3 tests/run-c03-human-feedback-harness.py --mana-root /Users/zel/projects/mana --profile stress
python3 tests/run-c03-human-feedback-harness.py --mana-root /Users/zel/projects/mana --profile desktop-long --platform macos
python3 tests/run-c03-human-feedback-harness.py --mana-root /Users/zel/projects/mana --profile soak --platform macos
```

Aggiungere l'equivalente Windows con path e bootstrap supportati. Distinguere `--help`, prerequisiti mancanti, fallimento di accettazione e run interrotto nei codici di uscita; nessuno di questi ultimi tre equivale a pass.

## 11. CI, documentazione e handoff finale

- PR: unit/widget/contract, C03 smoke e regressioni lettura. Job separati per stress e desktop; soak schedulato/manuale. Timeout limitati e upload di report parziale anche su failure/cancel.
- Registrare revisioni effettive di entrambi i repository e hash dei file rilevanti se dirty; la CI attuale usa Mana `develop`, che da solo non identifica una coppia compatibile. Scegliere un meccanismo esplicito per testare la coppia in sviluppo prima di promuovere il requisito di versione.
- Ogni run produce sotto `build/feedback-audit/run-*`: manifest versione, seed, action trace, risultati delle asserzioni, request/response sintetiche, operation ID, hash prima/dopo, tempi, risorse, screenshot e fallimenti. Preservare report e prove prima di eliminare esclusivamente le directory temporanee create dal runner.
- Aggiornare README, product boundary, architecture, contratti/compatibility matrix, documentazione UX ed E2E. Scrivere una breve guida «commento / risposta / decisione / piano aggiornato» e indicare dove vivono bozze e dati canonici.
- Nessun commit, PR o pubblicazione automatica richiesti da questo piano. Niente modifiche a progetti reali; i test e le rigenerazioni usano solo fixture temporanee.

La relazione finale di Terra deve elencare funzionalità realizzate, contratti e comandi effettivi, file cambiati nei due repository, verifiche con numeri reali e skip motivati, esiti v1/v2/macOS/Windows, durate e azioni dei run lunghi, risorse misurate e link alle prove. Riportare esplicitamente qualsiasi criterio non soddisfatto: «test verdi» o «UI completata» non sostituiscono la verifica del workflow e della persistenza.

## 12. Checklist finale di accettazione

- [ ] Commenti e risposte sopravvivono a restart e rigenerazioni e restano sul target corretto.
- [ ] Le bozze dichiarate salvate localmente sono recuperabili; scarto esplicito e nessuna pubblicazione implicita.
- [ ] Una decisione esplicita è registrata una sola volta, con motivazione e storia; opzioni stale/estranee sono respinte.
- [ ] Story Start riceve realmente i contributi e rispetta le decisioni compatibili; stato del piano e review restano veritieri.
- [ ] Nessuna riscrittura libera dei report generati o scrittura diretta dei record Mana dal client.
- [ ] Letture inspect rimangono deterministiche e senza scritture; capability e fallback preservano v1/vecchi producer/snapshot.
- [ ] Due finestre, ACK perso, crash e risposte tardive non causano perdita, duplicazione o contaminazione fra progetti.
- [ ] C03 e regressioni C00/C01/C02 eseguiti; gli E2E nativi sono distinti dai widget test.
- [ ] Stress, sessione desktop di 20 minuti e soak di 60 minuti eseguiti con trace e oracle, non soltanto predisposti.
- [ ] Supporto e limiti macOS/Windows dichiarati in base a esecuzioni effettive.
- [ ] Schermate ispezionate, flussi da tastiera verificati, report riproducibili e nessun criterio fallito nascosto.
