# Piano operativo per Terra o Sol: completamento e verifica Human Feedback

Data: 12 settembre 2026. Stato: pronto per lo sviluppo; nessun criterio di accettazione è attestato da questo documento.

## 1. Mandato e rapporto con il piano originale

Completare commenti Markdown, risposte e decisioni sugli artefatti di Story Start, rendendoli recuperabili e realmente utilizzabili nei workflow successivi. Questo documento ordina gli interventi sulla prima implementazione e integra il [piano funzionale originale](goal-terra-human-feedback-and-decisions.md), che conserva i requisiti di prodotto, le soglie e gli scenari dettagliati. In caso di differenze nella descrizione della baseline, usare questo documento e verificare il codice corrente; non ridurre implicitamente i requisiti originali.

Repository interessati:

- Familiar: `/Users/zel/projects/mana-familiar`, client, interfaccia, bozze e test.
- Mana: `/Users/zel/projects/mana`, contratto, storage, inspect, Story Start e test.

Questa consegna è un piano: non avvia implementazioni, agenti, commit o pubblicazioni. Quando viene assegnata per lo sviluppo, eseguire le fasi fino ai criteri di uscita, riportando gli eventuali impedimenti reali. Leggere le istruzioni applicabili nei due repository e preservare le modifiche preesistenti. Gestire i permessi richiesti dall'ambiente senza aggirarne i limiti.

Resta esclusa la modifica libera dei file Markdown generati. Il composer modifica contributi umani separati; decisioni, risoluzioni di thread e approvazioni hanno semantiche distinte. Nessun provider reale deve partire dal salvataggio o dai gate automatici qui descritti.

## 2. Baseline e limiti delle verifiche precedenti

La sessione precedente ha riportato verdi: 180 test Flutter con 4 skip, analisi statica, 9 test Python, harness C01/C02, build macOS debug, suite Mana zero-token, test del comando human-feedback e validazione repository. Sono risultati storici sulle suite esistenti, non prova del completamento di questa feature; non usarli come accettazione di C03, crash recovery, due finestre o soak.

Riscontri da riconfermare sul checkout iniziale:

| Area | Stato osservato | Conseguenza |
| --- | --- | --- |
| Commenti | Repository, pannello e comando CLI presenti | Base da completare, non riscrivere senza motivo |
| Concorrenza Mana | Revisione verificata senza lock; temporaneo condiviso in mutate/decide | Possibili interferenze anche fra target diversi |
| Crash/idempotenza | Record e ricevuta salvati separatamente | Retry dopo commit incompleto non garantito |
| Percorsi | Decision ID con slash e `..` usato nel nome file | Containment insufficiente da correggere prima della release |
| Letture | Il comando prepara directory anche per list | Verificare e ripristinare la garanzia no-write |
| Decisioni | Persistenza CLI, senza validazione delle alternative effettive | Registrazione non equivalente a scelta applicabile |
| Story Start/inspect | Integrazione feedback non trovata nei punti ispezionati | Workflow e capability da completare |
| Bozze | Store presente, non collegato nel percorso applicativo; risposte in memoria | Possibile perdita alla chiusura del pannello |
| Rigenerazioni | List seleziona la revisione esatta dell'artefatto | Contributi vecchi conservati ma non visibili sul nuovo report |
| UI | Composer elementare e flussi asincroni parziali | Mancano stati e protezioni di lifecycle |
| Test dedicati | Quattro test applicativi e un widget test, oltre al test CLI | Mancano C03 e prove prolungate della feature |

Punti di ingresso Familiar: `lib/application/human_feedback.dart`, `lib/presentation/human_feedback_panel.dart`, `lib/presentation/artifact_detail_view.dart`, `lib/presentation/project_observatory_page.dart`, `lib/app/mana_familiar_app.dart`, relativi test.

Punti di ingresso Mana: `scripts/mana-human-feedback.sh`, `scripts/bootstrap-project.sh`, `scripts/mana-inspect.sh`, `scripts/lib/story-start-scope-v2*`, contratti Story Start, test human-feedback, runner zero-token e validazione repository.

## 3. Sequenza di sviluppo e gate intermedi

Ordine: F0 → F1 → F2 → F3 → F4 → F5 → F6. Si possono preparare fixture e test delle fasi successive anticipatamente, ma nessuna fase passa sulla sola base di mock. Ogni intervento deve avere un requisito, una prova riproducibile e un esito registrato.

### F0 — Baseline riproducibile e contratto definitivo

1. Registrare commit, branch, stato dirty e hash dei file rilevanti di entrambi i repository. Identificare modifiche preesistenti e nuove; non fare reset o pulizie generiche.
2. Inventariare contratti, trasporto, storage applicativo, lifecycle desktop, watcher, choice log, consumer learning e runner esistenti. Verificare la matrice Story Start v1/v2 e le istruzioni Windows effettive.
3. Riprodurre i difetti prioritari solo su fixture temporanee: due scrittori con stessa revisione, target diversi, crash fra record e ricevuta, decision ID ostile, list su progetto senza storage, chiusura con bozza. Introdurre barriere deterministiche per le race; non affidarsi a sleep casuali.
4. Scrivere ADR, schemi e fixture request/response versionati: identità progetto/work item/artefatto/sezione/domanda/decisione; revisioni distinte; capability; comandi; errori; stato operazione; paginazione; collegamenti alle versioni precedenti.
5. Definire la strategia transazionale e il commit point. Preferire un meccanismo già supportato dal repository; se si mantiene storage a file, documentare lock, journal, recupero e ordine di pubblicazione. Atomic rename da solo non risolve la transazione multi-file.
6. Specificare limiti in byte UTF-8 e caratteri, cursori, cache, processi, timeout, retention delle ricevute e delle bozze. I limiti vanno dichiarati prima dei test.

Uscita: difetti riprodotti con test di regressione, contratto documentato, strategia di recupero concreta e elenco dei consumer da aggiornare. Non richiedere una scelta all'utente per normali dettagli implementativi.

### F1 — Storage Mana sicuro e transazionale (priorità bloccante)

- Separare ID logici e nomi file: usare una mappatura sicura, per esempio digest, conservando l'ID originale nel record e verificandolo in lettura. Non inserire ID arbitrari nei percorsi.
- Validare target realmente esistente, appartenenza al progetto/work item, revisione sorgente e riferimenti strutturati prima delle mutazioni. Non limitarsi alla forma della stringa.
- Controllare containment e symlink prima di creare directory o aprire file; includere `.mana`, antenati, directory finali, file e temporanei. Gestire i cambi fra controllo e uso entro il modello di accesso supportato, documentandone i limiti.
- Rendere list/inspect/status prive di scritture, anche al primo accesso e in caso di errore. Nessuna inizializzazione, migrazione o riparazione implicita nelle letture.
- Eseguire confronto revisione e commit sotto un unico confine di concorrenza. Un temporaneo deve essere esclusivo per operazione. Se si usano più lock, stabilire l'ordine e timeout per evitare deadlock.
- Rendere contributo e identità dell'operazione recuperabili insieme. Un crash dopo commit e prima della risposta deve consentire di ottenere lo stesso esito senza duplicazione; un crash prima del commit non deve pubblicare un contributo parziale.
- Aggiungere lookup dello stato per operation ID, retry stesso payload e rifiuto stessa chiave/payload diverso. La retention non deve rendere un vecchio retry una nuova scrittura silenziosa.
- Conservare la storia di commenti corretti, risoluzioni/riaperture e decisioni sostituite con autore dichiarato e timestamp producer; evitare perdita di provenienza.
- Definire migrazione esplicita dei record già prodotti dalla prima versione: backup recuperabile, versione riconosciuta, verifica, gestione interruzione e nessuna cancellazione automatica dei record sconosciuti.
- Garantire roundtrip del testo: niente perdita silenziosa di newline finali tramite command substitution o trim indiscriminato. Distinguere controllo di testo vuoto da normalizzazione del contenuto.

Uscita: test avversariali, race e crash passati; zero file modificati fuori dallo storage autorizzato; una sola mutazione per operazione confermata.

### F2 — Inspect, decisioni e consumo Story Start

- Esporre capability globali e per target; distinguere unsupported, offline, snapshot, errore e zero contributi. Conservare la compatibilità dei contratti inspect esistenti.
- Implementare letture paginate coerenti di thread, entry e decisioni, con conteggi, revisione della vista e cursori invalidati esplicitamente quando necessario.
- Esporre tutte le revisioni rilevanti con stati valid, stale, missing e ambiguous, o equivalenti documentati. Una rigenerazione non deve rendere invisibile la storia o riagganciare automaticamente una sezione diversa con lo stesso titolo.
- Per decide verificare decision ID, alternative pubblicate, option ID, stato, revisione del registro e revisione delle alternative. Rifiutare opzioni estranee, rimosse o scelte basate su dati superati.
- Integrare i contributi nel contesto reale del successivo Story Start con provenienza e stato. Le decisioni compatibili devono essere vincoli verificabili, non semplici note che il provider può ignorare.
- Verificare governor, esclusione fra rami, stime e review. Un provider che omette o contraddice una scelta non deve produrre un piano dichiarato valido.
- Distinguere registrazione della decisione, proiezione aggiornata e ripianificazione necessaria. Se serve un provider, esporre la necessità senza avviarlo al salvataggio.
- Coordinare rigenerazione e salvataggi sul controllo di pubblicazione: niente combinazioni incoerenti di report, decisioni e piano.
- Collegare v1 ai consumer esistenti dove supportato; dichiarare esplicitamente le azioni non disponibili. Evitare doppioni fra registro canonico, choice log e learning.

Uscita: fixture reale commento → scelta → nuovo Story Start → verifica del piano, per ciascun percorso supportato; casi incompatibili respinti o marcati da riconciliare.

### F3 — Client, bozze e lifecycle Familiar

- Completare DTO e parsing rigoroso con campi additivi tollerati e incompatibilità esplicite. Restituire risultati tipizzati reali: niente thread fittizi con target vuoto per rappresentare un ACK.
- Usare argomenti strutturati e JSON stdin; limiti di input/output, timeout, draining dei due stream, gestione dei processi e diagnostica utile senza payload privati nei log.
- Negoziare le capability prima di abilitare le azioni. Il semplice ritrovamento di uno script o di una revision non prova il supporto del target.
- Collegare lo store delle bozze dal bootstrap fino al pannello usando storage applicativo esterno al progetto. Namespace per progetto, work item, artefatto, composer/thread e finestra; test con directory temporanee.
- Persistire anche risposte e motivazioni decisionali. Debounce documentato, salvataggi serializzati, flush attendibile su navigazione e chiusura nativa; recupero di corruzione/quota/errori disco senza falsa conferma.
- Persistire chiave e payload prima dell'invio. Congelare lo snapshot inviato e proteggere il testo digitato nel frattempo: un ACK tardivo non deve cancellare una bozza più recente.
- Gestire bozza, salvataggio locale, invio, esito incerto, successo, conflitto ed errore. Dopo timeout verificare l'operazione; un retry identico riusa la chiave, una modifica esplicita produce una nuova operazione dopo riconciliazione.
- Separare restaurazione asincrona e digitazione: una bozza caricata in ritardo non deve sovrascrivere nuovo testo. Prevenire accessi a controller disposti e aggiornamenti sul progetto/target sbagliato.
- Scarto esplicito e pubblicazione non devono far ricomparire bozze cancellate tramite timer o callback ancora attivi. Due finestre non devono sovrascrivere le bozze l'una dell'altra.
- Invalidare solo dati pertinenti dopo mutazione; coalescing del watcher, niente refresh ricorsivi. Rilasciare controller, listener e processi; rendere bounded cache e richieste.

Uscita: test deterministici di navigazione, restart, perdita ACK, risposte fuori ordine, dispose e due finestre; nessuna perdita di testo dichiarato salvato.

### F4 — Interfaccia completa e accessibile

- Pannello commenti con conteggio, aperti/tutti, stato collegamento, cronologia e paginazione/lazy rendering. Layout affiancato su desktop ampio e leggibile su finestra compatta.
- Commento al documento o alla sezione solo con riferimenti del producer; risposte a domande strutturate dove disponibili.
- Composer Markdown con anteprima inerte, stato bozza, salvataggio/scarto e scorciatoie. Riutilizzare il renderer sicuro e valutare l'editor già disponibile; verificare link, HTML e codice ostile.
- Form decisione con domanda, alternative valide, motivazione, autore dichiarato, storia e conseguenze di una sostituzione. Stati distinti per scelta registrata e piano da aggiornare.
- Conflitti recuperabili con testo locale conservato e versione remota visibile; errori di caricamento con retry, senza spinner infinito o messaggi tecnici grezzi.
- Identità autore compatibile con nomi reali, spazi e Unicode secondo contratto. Non far apparire un autore dichiarato come autenticato.
- Test da tastiera, focus restituito al documento, screen reader, zoom 130%/200%, stringhe lunghe e molti thread. Catture almeno 1440×900 chiaro, 1024×768 scuro al 130%, 800×600 al 200%; ispezionare le immagini.

Uscita: percorsi completi usabili alle dimensioni previste, nessun overflow, anteprima sicura e tutti gli stati distinguibili anche senza colore.

## 4. F5 — Matrice dei controlli obbligatori

Ogni caso deve verificare uno stato osservabile, non soltanto chiamate a mock. Aggiungere il test che riproduce il difetto prima della correzione dove possibile.

| Gruppo | Casi minimi | Oracle |
| --- | --- | --- |
| Percorsi | traversal, slash/backslash, assoluti, Unicode, symlink antenato/finale/temporaneo e sostituito | Nessuna lettura/scrittura estranea; fixture sentinella intatta |
| Contratto | campi mancanti/additivi, versione sconosciuta, capability assente, target estraneo | Esiti tipizzati; lettura legacy invariata |
| Testo | multilinea, newline finali, italiano/emoji/combinati, CRLF/LF, backtick, `$()`, HTML | Roundtrip concordato; nessuna esecuzione |
| Limiti | soglia e oltre per body, input stdin, output, pagina e cache | Rifiuto prevedibile, nessun commit parziale/hang |
| Thread | crea, rispondi, correggi, risolvi, riapri | Storia e revisioni coerenti; review/lifecycle invariati |
| Decisioni | valida, estranea, rimossa, stale, sostituita | Scelta e storia valide; governor coerente |
| Race | stessa revisione; stessa chiave uguale/diversa; thread distinti; rigenerazione durante write | Una vittoria e conflitto dove previsto; nessun aggiornamento perso |
| Crash | prima commit, dopo commit/prima ACK, durante proiezioni/migrazione, lock abbandonato | Recupero deterministico; niente duplicati o falso successo |
| Bozze | flush, riavvio, scarto, quota, corruzione, due finestre, digitazione durante invio | Nessuna perdita del testo confermato o contaminazione |
| Async | load tardivo, ACK tardivo, cambio progetto, dispose, errore e retry | Nessun controller disposto usato; target corretto |
| Rigenerazioni | revision diversa, heading duplicato/rinominato, target assente, opzioni mutate | Storia visibile, stati espliciti, nessun riaggancio silenzioso |
| Letture | primo accesso, storage assente/corrotto, pagine con mutazioni | Zero scritture; nessun buco/doppione non segnalato |
| Workflow | provider omette/contraddice scelta; v1/v2; learning | Vincoli rispettati o pubblicazione bloccata; provenienza unica |
| Desktop | Back/Forward, cambio scheda/progetto, due finestre, Close/Quit nativi | Persistenza reale, risorse rilasciate, focus corretto |

### C03 e aggiornamento dei flussi E2E

Implementare `tests/run-c03-human-feedback-harness.py` o equivalente documentato, con producer reale su progetti temporanei e provider stub. Mantenere C01/C02 e la loro garanzia di sola lettura; le scritture appartengono al nuovo scenario C03.

Percorso principale: aprire artefatto → digitare bozza → navigare e riaprire → pubblicare → rispondere da seconda finestra → generare conflitto → recuperare → risolvere/riaprire → registrare decisione → rigenerare con Story Start → verificare contributi e piano → riavviare → confrontare stato recuperato.

Inserire errori anche nella parte finale: perdita ACK, processo interrotto, risposta tardiva, storage indisponibile, target rimosso e alternative cambiate. Tenere separati test widget, harness CLI/contratto e interazioni desktop native: uno non certifica gli altri.

Il runner mantiene un modello atteso indipendente delle operazioni accettate e confronta UI, inspect e fonte canonica ai checkpoint. Vietato costruire l'atteso leggendo la stessa proiezione sotto test. Registrare hash dei report generati per verificare che i commenti non li riscrivano.

### Profili lunghi e prestazioni

Eseguire i minimi del piano originale, integrati con il dataset e gli scrittori concorrenti indicati qui:

| Profilo | Carico | Uso |
| --- | --- | --- |
| smoke | percorso C03 completo, riavvio, conflitto e ACK perso; 3 seed × 100 azioni, 2 progetti, 10 documenti | PR |
| stress | 5 seed × 2.000 azioni, 3 progetti, 100 documenti, 2 scrittori concorrenti; dataset di 1.000 thread con 10 risposte ciascuno e un thread aggiuntivo da 1.000 risposte | job dedicato |
| desktop-long | almeno 20 minuti reali, 300 azioni, 2 finestre, 5 rigenerazioni, 3 riavvii, 10 guasti recuperabili | accettazione desktop |
| soak | almeno 60 minuti reali, 1.000 azioni e cicli di conflitto/rigenerazione/restart | pre-release o schedulato |

Il profilo omonimo del runner C03 copre esclusivamente il percorso producer/API e distribuisce le sue mutazioni nell'intera finestra; il suo report dichiara esplicitamente questo limite. Le due finestre, rigenerazioni, riavvii e guasti recuperabili richiedono un test E2E nativo distinto e non sono certificati dal runner CLI.

Generare il dataset con fixture dedicate rispettando il formato canonico e validandolo; le mutazioni sotto test passano dalle API reali. Usare seed/action trace riproducibili. Il tempo trascorso inattivo non sostituisce uso effettivo.

Misurare input p95 ≤100 ms in profile mode; latenza salvataggio nell'ultimo quarto ≤2× il primo a carico confrontabile; processi/listener/timer al baseline dopo teardown. Su working set fisso, dopo warm-up e quiescenza, crescita residua memoria ≤max(30 MiB, 15% baseline), con mediana di almeno tre campioni finali. Registrare RSS separatamente dalla memoria gestita, hardware, build e strumenti. Una misura non disponibile resta non verificata; non cambiare le soglie a posteriori per ottenere verde.

Uscita F5: tutti i casi applicabili passati con prove; nessuno skip richiesto considerato successo. Windows richiede runner Windows reale: build macOS o widget test non ne dimostrano il supporto.

## 5. F6 — Gate finale, CI e consegna

Integrare test human-feedback nei runner di validazione e zero-token Mana se ancora assenti. Aggiungere C03 smoke alla CI, job separati stress/desktop e soak schedulato/manuale con timeout e upload delle prove anche su failure/cancel. Identificare la coppia di revisioni Mana/Familiar verificata; il solo riferimento a `develop` non basta.

Comandi Familiar esistenti da eseguire sul risultato finale:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --no-pub
flutter test --no-pub
python3 -B -m unittest discover -s tests -p 'test_*.py'
tests/run-c01-zero-token-harness.sh --mana-root /Users/zel/projects/mana
tests/run-c02-semantic-observatory-harness.sh --mana-root /Users/zel/projects/mana
flutter build macos --debug
tests/run-macos-native-window-e2e.sh
git diff --check
```

In Mana: test human-feedback, validazione repository, contratti inspect e compatibilità consumer, integrazione/release gate Story Start e suite zero-token completa. Verificare le opzioni dei runner esistenti prima di invocarli. Per Windows eseguire build e flussi nativi nel relativo ambiente; per le misure UI produrre anche build profile.

Interfaccia proposta, da implementare e poi eseguire:

```sh
python3 tests/run-c03-human-feedback-harness.py --mana-root /Users/zel/projects/mana --profile smoke
python3 tests/run-c03-human-feedback-harness.py --mana-root /Users/zel/projects/mana --profile stress
python3 tests/run-c03-human-feedback-harness.py --mana-root /Users/zel/projects/mana --profile desktop-long
python3 tests/run-c03-human-feedback-harness.py --mana-root /Users/zel/projects/mana --profile soak
```

Ogni esecuzione ha directory unica `build/feedback-audit/run-*` con manifest, revisioni/hash dirty, comandi, exit code, seed, trace, conteggi/durate, report asserzioni, metriche e screenshot. Conservare il primo fallimento e i rerun separatamente. Pollare il session ID effettivo; la scomparsa di un processo non prova il successo. Non avviare copie concorrenti dello stesso gate per recuperare log persi.

Aggiornare README, product boundary, architecture, contratti, matrice compatibilità, guida commento/risposta/decisione/piano, storage e recupero bozze. Non conservare payload privati nei report: solo fixture sintetiche.

La consegna finale deve includere:

- Funzionalità completate e requisiti ancora aperti, riferiti alle fasi sopra.
- File cambiati nei due repository e decisioni ADR, inclusa migrazione/recupero.
- Risultati dei gate con exit code, numeri effettivi, skip e link alle prove.
- Matrice v1/v2, producer vecchio, snapshot/offline, macOS/Windows con esiti reali.
- Durate/azioni delle sessioni lunghe, risorse misurate e limiti rimasti.

## 6. Criterio finale di accettazione

- [ ] Percorsi, concorrenza e recupero dopo crash verificati; nessuna perdita o duplicazione di mutazioni confermate.
- [ ] Capability, identità e revisioni validate dal producer; letture sempre senza scritture.
- [ ] Bozze di commenti, risposte e decisioni collegate all'app e recuperabili dopo chiusura reale.
- [ ] Decisioni valide consumate da Story Start e verificate dal governor, con storia e provenienza.
- [ ] Contributi precedenti visibili e riconciliabili dopo rigenerazione.
- [ ] UI completa, accessibile e verificata visivamente; conflitti/esiti incerti recuperabili.
- [ ] C03 e regressioni eseguiti; stress, desktop-long e soak con prove e misure.
- [ ] Supporto piattaforme e incompatibilità dichiarati senza assimilare skip a pass.
- [ ] CI, documentazione e report aggiornati; nessun requisito fallito nascosto dal verde delle suite storiche.

## 7. Evidenza di esecuzione locale (2026-09-13)

Le seguenti prove sono state eseguite sulla coppia di checkout sporchi
registrata nei rispettivi manifest; non vanno interpretate come una build
rilasciabile finché le modifiche non sono revisionate e fissate in revisioni
immutabili.

| Prova | Esito | Evidenza |
| --- | --- | --- |
| C03 stress producer | passato: 10.000/10.000 create, 10.000 thread ID univoci, 25.003 record canonici, 2.178,788 s | `build/feedback-audit/run-1789241474-6535541fcf/` |
| C03 producer desktop-long | passato: 300/300 mutazioni, 1.200,507 s (minimo 1.200 s) | `build/feedback-audit/run-1789246424-d01943d089/` |
| C03 producer soak | passato: 1.000/1.000 mutazioni, 3.691,000 s (minimo 3.600 s), trace con ID univoci | `build/feedback-audit/run-1789247661-7981b16974/` |
| Mana human-feedback/inspect e zero-token | passati, inclusi recovery crash, indice target `ready/dirty` e Story Start governor/release gate | output del gate `tests/run-zero-token-acceptance.sh` |
| Familiar | `dart format`, `flutter analyze`, 194 test (4 skip harness espliciti), build macOS debug, C01/C02 | output del gate locale |
| E2E macOS nativo multi-finestra | passato: due processi Runner, focus in entrambe le direzioni, `Cmd-W` su una finestra e `Cmd-Q` sull'altra | `build/native-e2e/macos-1789290537/` |

Il primo stress interrotto per degrado da scansione completa rimane nella sua
directory di audit come baseline negativa; non è un pass. La correzione usa
indici target derivati, pubblicati atomicamente sotto lock. Un marcatore
`ready/dirty` forza il fallback ai record canonici in caso di crash tra rename
del thread e refresh della cache; i test coprono anche indice assente e
symlink non sicuro.

Restano deliberatamente **non certificati**:

- cinque rigenerazioni Story Start e tre riavvii osservati dalla UI nativa.
  Familiar non espone ancora un trigger di rigenerazione: C03 e i gate Mana
  verificano il producer, ma non possono sostituire questa prova desktop;
- build e flussi nativi su un runner Windows reale;
- misure profile-mode p95 input/salvataggio, RSS e teardown listener/timer.

Questi elementi mantengono aperte le checkbox F5/F6 pertinenti: nessun
workflow, skip o test widget deve essere promosso a successo per essi.

Non dichiarare la feature completa se uno di questi requisiti rimane aperto. Un impedimento di ambiente va riportato con la prova mancante e l'azione necessaria, conservando i risultati già ottenuti.
