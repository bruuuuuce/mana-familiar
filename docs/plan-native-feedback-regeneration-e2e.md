# Piano di implementazione: rigenerazioni e Human Feedback nel desktop nativo

Data: 13 settembre 2026. Stato: implementazione incrementale; questo
documento separa le prove già raccolte dai requisiti ancora aperti.

## Stato di questa iterazione

Completati e verificati: isolamento di preferenze/sessioni, due Runner sullo
stesso progetto, cinque pubblicazioni Story Start governate (V0/R1–R5), tre
restart nativi, focus, Close/Quit con flush atteso, fixture producer,
storia tra revisioni e manifesto di target stabili con stati `changed`,
`missing` e `ambiguous`. Le bozze hanno namespace per finestra e migrazione
dal formato precedente; il watcher ricarica il pannello aperto. Lo smoke
macOS ora apre il report con deep-link, seleziona un target stabile, compila
e pubblica un commento Unicode multilinea e una risposta nel pannello montato,
confrontandone la presenza sia nella UI sia nella lettura canonica Mana. Dopo
R1–R5 il driver aspetta la revisione esatta esposta dal documento montato. Uno
smoke distinto apre la form dell'implementation plan, registra una decisione
con alternativa valida e motivazione e confronta la scelta con lo stato
canonico Mana. Un terzo smoke apre due Runner sullo stesso target, conserva
bozze differenti in A/B con Close e Quit inviati entro il debounce di 350 ms,
e ne verifica il recupero dopo nuovi PID e dopo gli ulteriori restart B.

L'automazione macOS non può ancora individuare i singoli widget Flutter con
Accessibility: su questo embedder la finestra è esposta come un unico gruppo
AX anche con la semantica richiesta. Perciò lo smoke usa un bridge HTTP
loopback, attivo esclusivamente in build debug e limitato a callback dei
widget montati; non accede a repository o filesystem e non sostituisce Mana.
L'input di commento, risposta e decisione è quindi marcato
`flutter-widget-bridge`, mentre focus, Close/Quit e il fallback
`File → Close Window` restano azioni macOS reali. La decisione è separata da
R1–R5: una scelta richiede una ripianificazione governata e la fixture
deterministica delle cinque rigenerazioni non proietta ancora la scelta nel
decision register successivo. Rimangono aperti quel percorso integrato,
bozze di reply/decisione e tra progetti diversi, il profilo `desktop-long`,
gli episodi di fault richiesti e il gate Windows.

## Obiettivo e perimetro

Completare il percorso macOS con due finestre reali sullo stesso progetto, cinque rigenerazioni Story Start esterne, tre riavvii e verifica dei contributi e delle bozze dalla UI. Mana pubblica tramite la pipeline reale con provider stub deterministico; Familiar osserva i cambiamenti tramite i suoi watcher e client reali. Non occorre aggiungere un comando di rigenerazione al prodotto.

Repository coinvolti: Familiar e Mana. Preservare le modifiche preesistenti e leggere le istruzioni applicabili in entrambi. Le modifiche Mana riguardano fixture, runner e contratti necessari alla riconciliazione. Nessun provider reale, progetto personale o preferenza utente deve essere usato dai test.

Windows resta un gate distinto da eseguire su Windows reale. Non è richiesto per chiudere questo incremento macOS, ma rimane aperto nel piano generale.

## Baseline verificata e lacune

- `tests/run-macos-native-window-e2e.sh` avvia due Runner sullo stesso
  progetto con preferenze e sessioni isolate; verifica focus e terminazione.
  Il menu Open Project, l'intero ripristino bozze e il secondo progetto non
  sono ancora esercitati nell'E2E.
- Il gate usa root temporanee e ricontrolla il PID focalizzato immediatamente
  prima di ciascuna azione. Prova prima Cmd-W/Cmd-Q; Close può registrare il
  fallback nativo `File → Close Window` quando macOS non consegna un tasto
  sintetico alla finestra già dichiarata frontmost.
- `HumanFeedbackDraftStore` ha namespace per sessione, progetto, artefatto e
  composer; conserva revisioni precedenti e migra il formato vecchio. Rimane
  da provare dalla UI il recupero di reply, decisioni e progetti diversi. Lo
  smoke `draft-smoke` prova invece due bozze commento distinte sullo stesso
  target in A/B, Close/Quit entro il debounce e ripristino dopo restart.
- Close e Quit usano un handshake AppKit/Flutter che attende il flush. Il
  fallback non classifica la sola scomparsa di un PID come successo.
- La lettura della storia conserva target e revisione originali e Mana espone
  `valid`, `changed`, `missing` e `ambiguous`; i test producer coprono gli
  indici derivati.
- `ExplorerConfig` interpreta `preferencesRoot`, sessione, deep-link e i due
  argomenti del bridge. I recenti nativi usano una suite `UserDefaults`
  derivata dalla root temporanea.

Questi punti richiedono sviluppo e test, non soltanto l'orchestrazione di cinque chiamate. Correggere anche i commenti/documenti che attribuiscono al gate attuale prove di persistenza o rigenerazione non eseguite.

## P1 — Rendere il gate isolato e osservabile

1. Creare un orchestratore, nome proposto `tests/run-native-feedback-e2e.py`, con output univoco, timeout per fase e teardown dei soli processi creati dalla run. Conservare exit code reali, incluse terminazioni anomale; non classificare ogni processo scomparso come successo.
2. Introdurre configurazione esplicita per preferenze temporanee e sessione finestra. Propagarla ai processi aperti dal menu nativo insieme al Mana root. Isolare anche i recenti nativi: una cartella temporanea Dart da sola non basta.
3. Creare due finestre A/B sul medesimo progetto sintetico, con sessioni distinte nello stesso storage applicativo di test. Aggiungere un secondo progetto per verificare assenza di contaminazione. Coprire almeno una apertura attraverso il comando nativo di produzione.
4. Pilotare l'app macOS mediante Accessibility, con selettori stabili per documento, pannello, composer, anteprima, publish, stato collegamento e decisioni. Usare PID e identità finestra anziché il solo titolo. Se i widget non sono individuabili, aggiungere semantica accessibile utile anche al prodotto.
5. Completare subito una prova verticale: apertura artefatto → digitazione nativa → pubblicazione → testo e stato letti dalla UI → verifica canonica. Questo è il gate di fattibilità dell'automazione prima di estendere il runner.
6. Se serve un bridge di test Flutter, limitarlo alla build di test e all'interazione/osservazione dei widget; non deve chiamare direttamente il repository per sostituire le azioni UI. Documentare quali input sono nativi e quali passano dal driver. Close, Quit e cambio focus rimangono azioni macOS reali.

Uscita: prova verticale ripetibile su due finestre, preferenze reali intatte, nessun processo residuo. Accessibility assente produce `blocked`, mai `passed` o skip verde.

## P2 — Pubblicazioni riproducibili e contratto di riconciliazione

In Mana riusare le fixture e gli hook di `tests/story-start-scope-v2-integration.sh` e la pipeline `scripts/lib/story-start-scope-v2.sh`. Estrarre un helper riutilizzabile solo dove necessario. Il runner riceve root del progetto, scenario e percorso evidenza; usa bootstrap supportato e provider stub a input/output fissati.

Ogni rigenerazione deve attraversare normalizzazione, governor e pubblicazione effettiva; attendere il marker finale di pubblicazione coerente. Una riscrittura arbitraria del Markdown non conta come rigenerazione Story Start. Una mutazione equivalente può essere un test aggiuntivo del watcher, indicato separatamente.

Definire prima le identità stabili del documento e delle sezioni. La classificazione valid/changed/missing/ambiguous è responsabilità Mana: un heading uguale non prova continuità e un heading rinominato non prova perdita d'identità. Per legacy senza riferimenti affidabili mantenere commenti al documento e capability sezioni indisponibile.

Estendere la lettura per ritrovare tutte le revisioni di un artefatto con paginazione coerente. Preservare target e revisione originali di ciascun thread e fornire separatamente collegamento corrente e motivazione. Un target eliminato deve restare consultabile tramite una vista di storia/contributi accessibile anche senza il documento. Aggiornare client e UI: niente stato valid sintetico o attribuzione dei thread vecchi al target corrente.

Validare le scelte contro revisione e alternative correnti. Scelte registrate e poi rese incompatibili restano nella storia e non diventano vincoli applicabili. Riutilizzare le garanzie del governor; impedire pubblicazioni miste e scritture basate su alternative obsolete.

Compatibilità: capability esplicite per le nuove letture; producer vecchio e snapshot continuano a essere leggibili con limiti dichiarati. Test delle cache/indici derivati affinché non nascondano record di revisioni precedenti. Nessuna scrittura durante le letture inspect.

Uscita: test Mana dimostrano tutte le transizioni previste e il client ne mostra i risultati reali.

## P3 — Bozze e chiusura nativa affidabili

- Namespace stabile per sessione finestra, progetto, artefatto e composer. Conservare la revisione originale come dato della bozza; ritrovarla dopo rigenerazione senza ribasarla automaticamente.
- Recupero sessione dopo restart esplicito e deterministico. Due processi non possono acquisire silenziosamente la stessa sessione attiva; offrire il recupero delle sessioni precedenti senza sovrascrivere la bozza dell'altra finestra. Gestire anche le bozze nel vecchio formato senza perdita.
- Persistenza serializzata, flush che attende tutte le scritture già in corso, errori osservabili. Dichiarare “salvata localmente” solo dopo successo dello storage.
- Collegare Close e Quit a una procedura asincrona di preparazione della chiusura usando gli hook AppKit/Flutter appropriati, con protezione da rientranza. In caso di errore conservare la finestra e il testo con possibilità di riprovare o scartare esplicitamente. Non basarsi su dispose come unica garanzia.
- Conservare chiave idempotente e snapshot inviato anche se la chiusura arriva durante una richiesta. Un riavvio deve riconciliare un ACK perso senza creare un nuovo evento.
- Aggiornamento watcher: ricaricare documento e stato collegamento dopo una pubblicazione completa, preservando testo, selezione e focus. Coalescere gli eventi senza loop di refresh. Se il target sparisce, mostrare uno stato recuperabile e un accesso alla storia.

Uscita: test puntuali e nativi dimostrano recupero di commenti, risposte e motivazioni decisionali, comprese chiusure entro i 350 ms del debounce corrente.

## P4 — Sequenza E2E obbligatoria

Preparare una pubblicazione iniziale V0, un documento con target stabili, un target sezione per ciascun caso e una decisione strutturata con due alternative. Inserire dalla UI un commento, una risposta, una scelta e bozze differenti in A/B. L'atteso è dichiarato dalle fixture e dalle azioni inviate, non ricavato dalla proiezione sotto test.

| Passo | Pubblicazione / azione | Verifica dalla UI e dallo storage |
| --- | --- | --- |
| R1 | Rigenerazione identica, stessa identità e contenuto | Nuova esecuzione pipeline provata anche se hash invariati; thread ancora validi, nessun duplicato, bozze intatte |
| R2 | Contenuto modificato, identità stabile | Revisione aggiornata, contributi precedenti visibili come changed secondo contratto, focus e testo preservati |
| Restart 1 | Digitare e chiudere A con Cmd-W prima del debounce, riaprirla | Nuovo PID; bozza A recuperata esattamente, B viva e bozza B intatta |
| R3 | Rinominare un heading mantenendo ID e introdurre riferimenti ambigui su un altro target | Caso stabile distinto da ambiguous; nessun riaggancio basato sul titolo |
| Restart 2 | Quit nativo di B con motivazione o risposta non pubblicata, poi riapertura | Recupero del composer corretto; storia persistita invariata |
| R4 | Rimuovere un target pubblicato | Stato missing, testo e storia ancora raggiungibili, nessuna scrittura involontaria sul target eliminato |
| R5 | Cambiare le alternative della decisione | Scelta precedente conservata e incompatibilità esplicita; invio dalla vista obsoleta rifiutato senza perdita di motivazione |
| Restart 3 | Dopo commit producer con ACK perso, terminare il solo processo test e riavviarlo | Stessa operazione riconciliata, un solo evento canonico, eventuale testo più recente preservato |

Il terzo restart prova il recupero da interruzione; i primi due provano Close/Quit. Documentare il punto esatto del fault, distinguendolo da un arresto normale. R1–R5 sono cinque rigenerazioni successive a V0, non cinque avvii totali.

Tra i checkpoint: cambio focus A/B, Tab/Shift-Tab, apertura/chiusura pannello e ritorno al documento, filtro aperti/tutti, anteprima Markdown, navigazione via UI. Provocare inoltre due reply concorrenti sulla stessa revisione: una accettata e un conflitto con testo recuperabile. Verificare la visibilità remota nell'altra finestra.

Ad ogni checkpoint confrontare: valori e stati visibili della UI; inspect/API reali; record canonici. Asserire ID e conteggi attesi, revisione, testo Unicode/multilinea completo e assenza di duplicati. I commenti non cambiano gli hash degli output generati; gli hash possono cambiare soltanto nei passi di rigenerazione previsti. Conservare screenshot significativi e ispezionarli, ma non usarli come unico oracle.

## P5 — Test puntuali e guasti

| Area | Test necessari |
| --- | --- |
| DTO/letture | Target originale, quattro stati, stato sconosciuto esplicito, storia tra revisioni, paginazione durante pubblicazione, capability vecchia |
| Bozze | Due processi sul medesimo target, recupero sessioni, migrazione, flush in corso, errore disco, caricamento tardivo, scarto, ACK tardivo |
| Lifecycle | Close e Quit attendono flush; errore impedisce chiusura silenziosa; doppia richiesta non avvia due teardown; crash recupera solo testo già persistito |
| Watcher/UI | Pubblicazione parziale/finale, cambio progetto durante load, target missing accessibile, focus e testo preservati, niente controller disposto utilizzato |
| Producer | Cinque scenari governati, revisione obsoleta, alternative mutate, cache/indici coerenti, storico conservato, consumo delle scelte compatibili |
| Runner | Timeout, crash inatteso, precondizione Accessibility assente, evidenza incompleta, isolamento preferenze, nessun segnale inviato a processi estranei |

Distribuire nel profilo lungo almeno dieci episodi recuperabili, anche nell'ultimo quarto della run: due conflitti, due ACK persi, due letture fallite, due scritture bozza fallite, due risposte ritardate. Ogni episodio deve essere iniettato, osservato e recuperato con una specifica asserzione. Non contare timeout casuali o attese come guasti esercitati.

## P6 — Profili, evidenze e CI

Interfacce disponibili:

```sh
python3 tests/run-native-feedback-e2e.py --mana-root /path/to/mana --profile smoke
python3 tests/run-native-feedback-e2e.py --mana-root /path/to/mana --profile decision-smoke
python3 tests/run-native-feedback-e2e.py --mana-root /path/to/mana --profile draft-smoke
```

- Smoke (disponibile): commento e risposta canonici, R1–R5 osservate dal documento UI e tre restart; timeout complessivo iniziale 15 minuti. Il timeout è un limite operativo, non un tempo minimo da consumare.
- Decision-smoke (disponibile): commento e risposta in A, una decisione nell'implementation plan B, stato canonico della scelta e lifecycle; deliberatamente senza rigenerazioni successive alla scelta.
- Draft-smoke (disponibile): due bozze commento differenti sul medesimo target e in sessioni A/B; Cmd-W e Cmd-Q sono inviati entro 350 ms dal testo, il fallback `File → Close Window` resta nativo e viene timestampato, e i testi si ritrovano dopo i rispettivi restart e dopo i tre restart B. Il driver controlla inoltre che una bozza non compaia nella storia canonica Mana.
- Desktop-long (da implementare, comando previsto `--profile desktop-long`): almeno 20 minuti e 300 azioni UI distribuite, due finestre, cinque rigenerazioni, tre restart, dieci episodi recuperabili. Contare separatamente azioni UI, mutazioni accettate, rigenerazioni, restart e guasti; i sondaggi del runner non sono azioni utente.
- Soak da 60 minuti/1.000 azioni: estensione successiva alla stabilizzazione del profilo desktop-long. Il C03 producer già esistente resta un controllo distinto.

Per run: manifest con revisioni Mana/Familiar, digest delle modifiche locali e del bundle, modalità build, sistema, seed, comandi ed exit code; trace timestampata, PID/sessioni, hash delle pubblicazioni, asserzioni, screenshot e risultato `passed/failed/blocked`. Persistenza incrementale anche su errore e cancellazione. Usare solo payload sintetici. Conservare i fallimenti e i rerun in directory diverse.

Per le prestazioni usare build profile, hardware registrato e carico confrontabile: input p95 ≤100 ms; salvataggio ultimo quarto ≤2× primo; RSS separata da memoria gestita, crescita residua ≤max(30 MiB, 15% baseline) dopo warm-up con mediana di tre campioni finali. Processi/listener/timer devono tornare al baseline dopo teardown. Il debug smoke non certifica queste soglie; misure assenti restano aperte.

CI: test puntuali ad ogni PR; job desktop macOS manuale/schedulato su runner con sessione grafica e Accessibility già configurati. Fare un preflight sull'ambiente scelto prima di considerarlo adatto. Upload delle evidenze anche su failure; test richiesti bloccati non producono verde. Windows richiede un driver e un'esecuzione dedicati.

## Sequenza di consegna e criteri finali

Ordine suggerito dei commit: (1) isolamento e prova verticale nativa; (2) fixture e contratto Mana, con test; (3) parsing/storia/watchers Familiar; (4) sessioni bozze e handshake di chiusura; (5) orchestrazione completa e guasti; (6) CI, documentazione ed evidenze. I percorsi sono proposti: riusare helper esistenti quando coprono il requisito.

Eseguire formattazione, analisi, test Flutter/Python pertinenti e build macOS; poi C01/C02, C03 smoke e regressioni Mana human-feedback/inspect/Story Start e zero-token se modificati i relativi componenti. Rileggere gli argomenti dei runner prima dell'esecuzione. Eseguire infine smoke nativo e desktop-long sullo stesso stato finale; non rilanciare stress già verdi senza una modifica che lo giustifichi.

- [x] Commento e risposta UI verificati nel thread canonico; decisione UI verificata nello stato canonico, in smoke separati.
- [x] Cinque pubblicazioni reali governate, ciascuna osservata dalla UI nello smoke commenti/risposte.
- [x] Due finestre sul medesimo progetto e target, con bozze indipendenti e focus verificato.
- [x] Tre restart B con nuovi PID e ripristino verificato; Close/Quit senza perdita dei testi A/B previsti.
- [ ] Storia raggiungibile dopo revisioni nuove, target rimosso e alternative mutate.
- [ ] Conflitti/ACK persi recuperati senza perdita o duplicazione di contributi.
- [ ] Preferenze reali intatte, cleanup limitato alla run, nessun processo residuo.
- [ ] Smoke e desktop-long passati con prove complete; metriche riportate con modalità build corretta.
- [x] README e piano generale aggiornati distinguendo quanto verificato da Windows/soak o altri requisiti ancora aperti.

La durata d'implementazione va rivalutata dopo P1/P2: la stima precedente di una giornata non includeva tutte le lacune sopra rilevate. Le esecuzioni richieste restano brevi o da 20 minuti; non richiedono due giorni di run continua.
