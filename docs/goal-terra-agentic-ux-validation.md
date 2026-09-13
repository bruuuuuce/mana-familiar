# Goal per Terra: rendere verificabile la valutazione agentica UX

## Obiettivo

Trasformare il primo harness UX di Mana Familiar in un sistema che separi
l'osservazione delle schermate dalla verifica rispetto ai dati e misuri la propria
affidabilità tramite casi di controllo. Implementare, eseguire e documentare il
risultato; non limitarsi a proporre modifiche.

Il risultato deve permettere di distinguere tre cose: il percorso funziona,
l'interfaccia comunica correttamente le informazioni, il valutatore è sufficientemente
calibrato per sostenere quel giudizio. Un esito positivo del primo controllo non
implica un esito positivo degli altri.

## Contesto verificato

- Repository: `/Users/zel/projects/mana-familiar`, applicazione desktop Flutter.
- Harness: `tests/run-agentic-ux.py`.
- Scenario e catture: `test/agentic_ux_test.dart`.
- Prompt: `tests/ux-review-prompt.md`.
- Test del validatore: `tests/test_agentic_ux_runner.py`.
- Documentazione: `docs/agentic-ux-testing.md` e relativo collegamento nel README.
- Ultima verifica: 160 test Flutter superati, 4 integrazioni saltate; 6 test Python
  superati; analisi statica pulita. Questi numeri sono una baseline, non risultati
  da riportare senza una nuova esecuzione.
- Lo scenario attuale produce otto schermate: quattro stati in due configurazioni
  (1440×900 chiaro; 1024×768 scuro con testo al 130%). Carica Roboto e Material Icons.
- La navigazione è programmata; l'agente giudica immagini. Non è un test di
  esplorazione autonoma del desktop né dell'intera applicazione avviata.
- Il prompt attuale contiene sia le risposte di riferimento sia un giudizio
  esplicito sulla contraddizione tra aggiornamento fallito e stato rassicurante.
  Il giudizio risulta quindi condizionato.
- Le catture mostrano due problemi reali: un lavoro `Blocked` senza spiegazione
  nel dossier e `Nothing needs attention` insieme a dati mancanti/refresh fallito.
  Non usare questi risultati come risposte da suggerire all'osservatore.

Il worktree contiene già modifiche e file non tracciati relativi all'harness.
Leggere le istruzioni applicabili e lo stato Git prima di intervenire; preservare
il lavoro esistente. I report storici sotto `build/ux-audit/` sono artefatti locali
ignorati da Git e potrebbero non essere disponibili in un altro checkout.

## Ambito e vincoli

- Modificare harness, fixture di test, prompt, validazione dei report e documentazione.
- Usare soltanto dati sintetici; non aprire progetti reali o inviare dati utente.
- Mantenere `flutter test` e la generazione delle catture utilizzabili senza un modello.
- L'invocazione agentica deve restare esplicita e documentare l'uso di token.
- Non modificare l'interfaccia di produzione per far passare la valutazione.
- Non avviare esplorazione autonoma del desktop, migrazioni di framework o refactoring
  estranei. Non pubblicare, distribuire o rendere obbligatorio il giudizio UX in CI.
- Non cambiare il modello configurato silenziosamente. Terra è l'agente incaricato
  dell'implementazione; la scelta del modello valutatore deve essere esplicita e registrata.
- Non richiedere un altro via libera per normali modifiche locali e verifiche già
  comprese nel goal. Rispettare comunque eventuali approvazioni imposte dagli strumenti.

## Piano di implementazione

### 1. Definire il contratto della valutazione

Separare i dati in tre artefatti versionati:

1. **Manifest per l'osservatore:** immagini, dimensioni, domanda neutrale per ciascun
   checkpoint e sole informazioni necessarie al compito.
2. **Oracle riservato:** fatti dello scenario, risposte corrette o legittimamente
   non determinabili e aspettative dei casi di controllo.
3. **Report:** osservazioni, confronto con l'oracle, risultati della calibrazione
   ed eventuali errori tecnici, conservati separatamente.

Le domande non devono incorporare la risposta: preferire «Qual è lo stato del
lavoro?» o «Quale azione è indicata?» a domande che anticipino un refresh fallito.
Usare identificativi opachi per immagini e casi: nomi come `broken`, `healthy` o
`unavailable` non devono svelare al primo agente la classificazione attesa.

### 2. Implementare osservazione e confronto separati

- Il primo passaggio riceve soltanto immagini e manifest neutrale. Per ogni domanda
  produce risposta, evidenza visibile/localizzazione e un'esplicita indicazione di
  incertezza. Può dichiarare che l'informazione non è determinabile.
- Non deve ricevere codice, oracle, risultati precedenti, classificazioni attese o
  istruzioni che prescrivano un rilievo. Isolare il contesto anche rispetto ai file
  accessibili e agli strumenti: una semplice richiesta di non leggere non equivale
  a una separazione tecnica. Documentare ogni limite residuo.
- Un secondo passaggio distinto confronta l'osservazione con l'oracle. Preferire
  confronti deterministici per campi strutturati; usare un valutatore separato dove
  serve interpretare testo libero. Conservare immutabile l'output del primo passaggio.
- Separare fedeltà informativa, leggibilità e utilità del compito. Evitare che una
  media alta nasconda una comunicazione falsa o un compito non completabile.
- Validare forma, completezza e riferimenti dei report. Il validatore strutturale
  non deve essere descritto come prova che l'evidenza visiva sia vera.

### 3. Aggiungere una calibrazione con controlli positivi e negativi

Preparare almeno quattro coppie di fixture controllate. In ogni coppia variare un
solo aspetto rilevante, mantenendo comparabile il resto:

| Dimensione | Controllo corretto | Difetto intenzionale |
| --- | --- | --- |
| Copertura dati | Incertezza esplicita quando mancano dati | Assenza di dati presentata come successo |
| Stato review | Stato sconosciuto dichiarato | Stato sconosciuto presentato come approvato |
| Identità | Problema associato chiaramente al lavoro | Problema senza associazione, con più lavori plausibili |
| Leggibilità | Informazione essenziale interamente leggibile | Informazione essenziale troncata o coperta |

Le varianti intenzionalmente difettose devono vivere soltanto nei test. Renderizzare
widget reali o composizioni di controllo documentate, senza alterare PNG dopo la
cattura. Distinguere controlli del valutatore e schermate dell'applicazione reale:
superare i primi non dimostra che l'app sia corretta.

Verificare visivamente tutte le fixture prima di usare i risultati. I controlli
corretti devono rendere davvero risolvibile il compito. Definire le aspettative e
le regole di conteggio prima dell'esecuzione agentica.

### 4. Misurare e conservare gli esiti

- Eseguire ogni controllo almeno due volte con la stessa configurazione dichiarata.
  Non ripetere selettivamente un caso finché passa e non scartare i risultati sfavorevoli.
- Riportare conteggi di difetti rilevati, difetti mancati, falsi allarmi, controlli
  corretti riconosciuti e risposte non valutabili. Precisare il denominatore: non
  trattare giudizi su una piccola suite come stime generalizzabili dell'usabilità.
- Separare errori tecnici, incertezza dell'osservatore e disaccordo sulla gravità.
- Registrare versione del codice e degli input (incluso worktree modificato), hash
  di prompt/oracle/immagini, modello e configurazione effettivamente disponibili,
  versione CLI/Flutter, data, sequenza delle azioni e risultati grezzi. Non salvare segreti.
- Generare un report leggibile in Markdown oltre al JSON, con riferimenti alle immagini.
- Mantenere esiti distinti per esecuzione incompleta, rilievi UX e calibrazione non
  soddisfacente. Documentare l'eventuale evoluzione degli exit code esistenti.
- Il risultato soggettivo resta informativo per la CI. Dichiarare esplicitamente
  eventuali limiti di calibrazione; non abbassare soglie per ottenere un esito positivo.

### 5. Verificare il sistema e rieseguire il caso reale

- Aggiungere test significativi contro contaminazione dell'input dell'osservatore,
  report mancanti o malformati, checkpoint duplicati, riferimenti inventati e
  aggregazioni che nascondano errori gravi o scartino risposte non valutabili.
- Verificare che un errore del modello, un timeout o un input incompleto non possano
  produrre un successo e che i report di esecuzioni precedenti non vengano riutilizzati.
- Rieseguire lo scenario PAY-42 con la nuova procedura. Non assumere che debba
  riprodurre i punteggi storici; confrontare osservazioni e prove, spiegando le differenze.
- Aggiornare documentazione e comandi riproducibili per cattura, calibrazione e audit.

## Criteri di completamento

- [ ] Il primo osservatore non riceve risposte attese, giudizi prescritti o nomi rivelatori.
- [ ] Osservazione, oracle e confronto hanno contratti distinti, documentati e testati.
- [ ] Esistono almeno quattro coppie di controllo visivamente verificate, con due
  esecuzioni per caso e risultati completi conservati.
- [ ] Il report rende visibili falsi positivi, difetti mancati e casi non valutabili.
- [ ] Una nuova esecuzione PAY-42 produce immagini, osservazioni e confronto tracciabili.
- [ ] L'assenza di un modello non impedisce i test locali; gli errori del modello
  non vengono mascherati come successi.
- [ ] Analisi statica e test pertinenti passano; eventuali problemi preesistenti sono distinti.
- [ ] La documentazione specifica cosa è stato verificato e cosa rimane escluso.
- [ ] Nessuna modifica dell'interfaccia di produzione e nessun giudizio UX obbligatorio in CI.

Il goal può essere completato con un risultato di calibrazione negativo, purché
misurato e riportato correttamente: l'obiettivo è una verifica onesta e riproducibile,
non far risultare buoni il valutatore o l'app. Se l'esecuzione agentica è impedita
da autenticazione o strumenti mancanti, completare il lavoro locale possibile e
segnalare precisamente la verifica rimasta incompleta; non dichiarare il goal concluso.

## Verifica finale e consegna

Eseguire almeno:

```sh
dart format --output=none --set-exit-if-changed test/agentic_ux_test.dart
flutter analyze --no-pub
flutter test --no-pub
python3 -B -m unittest discover -s tests -p 'test_agentic_ux_runner.py'
git diff --check
```

Adattare i percorsi se il refactoring divide i test in più file. Eseguire inoltre
cattura, calibrazione e audit con i nuovi comandi documentati. I test esistenti
possono richiedere fixture dal checkout Mana adiacente: non nascondere dipendenze
mancanti aggiungendo skip silenziosi.

Consegnare un riepilogo con file modificati, comandi eseguiti, risultati effettivi,
collegamenti ai report e alle immagini, limiti residui e raccomandazione sul grado
di affidabilità del valutatore. Non creare commit, PR o pubblicazioni salvo richiesta.

## Lavoro successivo, fuori da questo goal

1. Correggere in produzione causa/prossimo passo dei lavori bloccati e stati di
   copertura insufficiente, con test deterministici e confronto UX prima/dopo.
2. Ampliare i compiti a documenti, evidenze, cataloghi grandi e navigazione da tastiera.
3. Introdurre un agente che scelga autonomamente le azioni nel desktop, misurando
   successo del compito e tentativi falliti, senza confonderlo con l'attuale navigazione scriptata.

## Testo da passare a Terra come goal

> Implementa integralmente il piano in `docs/goal-terra-agentic-ux-validation.md`.
> Rendi neutrale e verificabile la valutazione UX separando osservazione e oracle,
> aggiungi i controlli di calibrazione, esegui le verifiche e consegna report con
> prove e limiti. Preserva le modifiche esistenti; non modificare l'interfaccia di
> produzione. Prosegui fino ai criteri di completamento del documento e non
> considerare un report negativo un motivo per alterare le aspettative.
