# Goal per Terra: correggere gli stati UX ambigui e rendere più affidabile il valutatore

## Obiettivo

Implementare e verificare le correzioni emerse dall'audit agentico UX di Mana
Familiar. Il lavoro deve migliorare due sistemi distinti:

1. l'interfaccia di produzione, affinché dati mancanti, refresh falliti, lavori
   bloccati e associazioni tra problemi e lavori non inducano conclusioni false;
2. il valutatore UX, affinché riconosca con maggiore affidabilità contraddizioni
   informative e problemi di leggibilità senza ricevere risposte suggerite.

Implementare, eseguire e documentare il risultato. Non considerare il goal concluso
solo perché i test funzionali passano o perché una singola esecuzione agentica non
trova problemi.

## Baseline verificata

- Repository: `/Users/zel/projects/mana-familiar`, applicazione desktop Flutter.
- UI principale coinvolta: `lib/presentation/project_observatory_page.dart`.
- Test di resilienza: `test/project_observatory_resilience_test.dart`.
- Test del dossier: `test/work_item_dossier_test.dart`.
- Scenario e fixture UX: `test/agentic_ux_test.dart` e
  `test/agentic_ux_calibration_test.dart`.
- Runner, prompt e validatore: `tests/run-agentic-ux.py`,
  `tests/ux-review-prompt.md`, `tests/test_agentic_ux_runner.py`.
- Documentazione: `docs/agentic-ux-testing.md`.
- Ultimo audit completo locale:
  `build/ux-audit/run-ghhtrhoj/report.md`.
- Ultima suite verificata: analisi statica pulita; 161 test Flutter superati e
  4 integrazioni saltate perché richiedono harness dedicati; 6 test Python superati.
  Questi numeri sono una baseline e devono essere sostituiti dai risultati di una
  nuova esecuzione.

L'audit PAY-42 riesce a ricavare le risposte attese nei due viewport, ma mostra
problemi reali nell'interfaccia:

- con copertura `none` e refresh fallito, il banner di errore convive con
  `Nothing needs attention`, formulazione che può essere letta come stato sano;
- un lavoro `Blocked` non presenta nel dossier, con sufficiente prossimità, causa,
  lavoro interessato e prossimo passo già forniti da `ManaAttentionItem`;
- nell'overview il problema è navigabile verso il lavoro, ma la riga di attenzione
  non rende sempre esplicita l'identità del lavoro interessato.

La calibrazione del valutatore è insufficiente: nelle due ripetizioni ha mancato
sia lo stato review intenzionalmente presentato come `approved`, sia l'azione
essenziale troncata. Questo è un limite del valutatore, non una prova che le stesse
schermate esistano nell'applicazione reale.

Il worktree contiene già modifiche non committate relative all'harness. Preservarle
e leggere lo stato Git prima di intervenire. Gli artefatti sotto `build/ux-audit/`
sono locali e ignorati da Git.

## Ambito e vincoli

- Modificare la UI di produzione soltanto per correggere i problemi descritti.
- Aggiungere test deterministici prima/durante i fix e aggiornare scenario,
  validatore, prompt e documentazione quando necessario.
- Usare soltanto dati sintetici. Non aprire progetti reali e non inviare dati utente.
- Non cambiare il modello configurato silenziosamente e registrare quello usato.
- Non incorporare nel prompt dell'osservatore le risposte PAY-42, i difetti attesi,
  i nomi delle varianti o istruzioni che prescrivano un finding.
- Non rinominare fixture, abbassare soglie, indebolire oracle o ritoccare PNG per
  ottenere un risultato positivo.
- Mantenere cattura e test locali utilizzabili senza modello.
- Il giudizio agentico resta informativo e non diventa obbligatorio in CI.
- Non introdurre esplorazione autonoma del desktop, migrazioni di framework,
  refactoring estranei, pubblicazioni, commit o PR.
- Un esito di calibrazione ancora negativo è accettabile se misurato e spiegato.

## Piano di implementazione

### 1. Rendere onesto lo stato di dati mancanti o non aggiornati

Separare esplicitamente tre condizioni nell'overview:

- dati completi e nessuna attenzione riportata;
- dati disponibili ma parziali/non conclusivi;
- refresh fallito o dati non disponibili.

`Nothing needs attention` e l'icona positiva devono apparire soltanto quando la
copertura consente davvero quella conclusione e non vi è un errore di refresh che
la renda obsoleta. Con copertura `none`, dati assenti o refresh fallito, mostrare
invece uno stato neutro/di avviso che dica:

- quali dati non sono disponibili o potrebbero essere obsoleti;
- che la salute del progetto non è determinabile;
- quale azione è disponibile, per esempio riprovare il refresh;
- quando applicabile, che sono mostrati gli ultimi dati riusciti senza presentarli
  come stato corrente certo.

Non dedurre “sano” da una lista vuota. Non nascondere contenuti stale ancora utili,
ma differenziarli visivamente e semanticamente dallo stato corrente.

Aggiornare `test/project_observatory_resilience_test.dart` sostituendo l'aspettativa
che oggi accetta contemporaneamente refresh fallito e `Nothing needs attention`.
Aggiungere almeno questa matrice deterministica:

| Copertura | Refresh | Attenzioni | Risultato richiesto |
| --- | --- | --- | --- |
| completa | riuscito | vuote | stato positivo consentito |
| parziale | riuscito | vuote | conclusione limitata, non “sano” |
| none | riuscito | vuote | salute non determinabile |
| qualsiasi | fallito | vuote | dati stale/incompleti, nessun successo rassicurante |
| qualsiasi | fallito | presenti | attenzione preservata e marcata come potenzialmente stale |

Usare le nozioni di copertura già presenti nei modelli; non introdurre euristiche
basate sul testo visualizzato.

### 2. Esporre causa e prossimo passo dei lavori bloccati

Nel dossier, soprattutto nella sezione Overview, presentare vicino allo stato
`Blocked` un riepilogo strutturato delle `attentionItems` appartenenti al lavoro:

- etichetta/categoria e severità del problema;
- associazione esplicita al lavoro tramite etichetta umana e ID;
- `nextAction` quando disponibile;
- assenza esplicita del prossimo passo quando il producer non lo fornisce, senza
  inventarne uno;
- collegamento agli artefatti correlati quando già supportato dalla navigazione.

Evitare di mostrare soltanto il badge `Blocked`: lo stato deve essere comprensibile
e azionabile senza dover tornare all'overview del progetto. Se più problemi sono
presenti, conservarne identità e severità senza comprimerli in una frase ambigua.

Aggiungere test in `test/work_item_dossier_test.dart` o in un file dedicato usando
fixture sintetiche locali, senza dipendere obbligatoriamente dal checkout Mana
adiacente. Coprire almeno:

- blocked con causa e `nextAction`;
- blocked senza `nextAction`;
- più attention item dello stesso lavoro;
- nessun attention item, evitando contenitori vuoti o copy inventato;
- layout compatto e testo al 130%, senza overflow o troncamento dell'azione.

### 3. Rendere esplicita l'associazione attenzione-lavoro

Nell'overview, ogni riga di attenzione deve mostrare l'identità leggibile del lavoro
interessato oltre alla descrizione del problema. Preferire titolo + ticket/ID umano;
gli identificatori tecnici non devono dominare la gerarchia.

L'interazione deve continuare ad aprire esattamente il lavoro indicato. Se il
producer fornisce un riferimento non risolvibile, non associare silenziosamente il
problema a un altro lavoro: mostrare una condizione non risolta e impedire una
navigazione fuorviante.

Aggiungere test per:

- un problema associato a un solo lavoro;
- due lavori plausibili, verificando che l'associazione resti esplicita;
- `workItemId` non risolvibile, con degradazione onesta;
- identità leggibile nei due viewport dello scenario UX.

### 4. Preservare correttamente lo stato review sconosciuto

Lo stato `unknown` attuale è correttamente distinto da `approved` e va preservato.
Consolidare questa proprietà con test espliciti per `unknown`, `approved`, stato di
attesa supportato dal modello e dati non disponibili. Badge, colore, icona e copy
non devono presentare `unknown` come approvazione implicita.

Non aggiungere verità esterne all'app. La UI deve rappresentare soltanto ciò che il
producer ha comunicato e indicare l'assenza di informazione quando necessario.

### 5. Migliorare il valutatore senza contaminarlo

Correggere la debolezza di calibrazione attraverso il contratto generale, non
insegnando le risposte dei singoli controlli. Estendere l'output dell'osservatore
con valutazioni strutturate e separate per ciascun checkpoint:

- `information_fidelity`: la schermata distingue fatto noto, ignoto e stale;
- `readability`: l'informazione necessaria è interamente visibile e leggibile;
- `task_usefulness`: la domanda è risolvibile e l'azione è utilizzabile;
- presenza di contraddizioni tra messaggi visibili;
- certezza e `not_determinable` già previsti.

La domanda principale e la classificazione del difetto devono essere valutate
separatamente: leggere correttamente la parola `approved` non significa riconoscere
che essa è una falsa rappresentazione rispetto all'oracle. Il secondo passaggio,
che possiede l'oracle, deve poter classificare deterministicamente la risposta come
corretta o falsa anche quando l'osservatore non produce spontaneamente un finding.

Per la leggibilità, richiedere all'osservatore di dichiarare se il testo essenziale
è completamente visibile, parzialmente visibile o non determinabile, citando il
segmento e la posizione. Non dire che una fixture è troncata.

Mantenere il primo passaggio tecnicamente isolato. L'oracle, il codice, i nomi
rivelatori e i risultati precedenti non devono entrare in `observer-input-*`.
Conservare immutabile l'output grezzo prima del confronto.

### 6. Rafforzare confronto, metriche e test del runner

Aggiornare `tests/test_agentic_ux_runner.py` con test che provino almeno:

- nessun campo dell'oracle nel manifest/schema/prompt dell'osservatore;
- bundle dell'osservatore contenente soltanto file consentiti;
- report mancante, JSON malformato, checkpoint mancante/duplicato o inventato;
- errore modello, timeout o output incompleto con exit code di incompletezza;
- nessun riuso di output da directory precedenti;
- risposta testualmente corretta ma fedeltà falsa rilevata dal confronto;
- informazione troncata classificata come difetto anche se il modello ne indovina
  semanticamente il contenuto;
- falsi allarmi su controlli corretti;
- risposte `not_determinable` conservate nel denominatore;
- nessuna media capace di nascondere un errore grave.

Calcolare e riportare separatamente, per coppia, variante e ripetizione:

- controlli corretti riconosciuti;
- difetti intenzionali rilevati;
- difetti mancati;
- falsi allarmi;
- risposte non valutabili;
- errori tecnici;
- disaccordi di gravità, se presenti.

Definire le regole di conteggio nel codice e nella documentazione prima della nuova
esecuzione agentica. Non reinterpretare manualmente un output sfavorevole per
trasformarlo in successo.

### 7. Aggiornare lo scenario PAY-42 e produrre confronto prima/dopo

Aggiornare le fixture sintetiche PAY-42 soltanto quanto necessario per esercitare
la nuova UI, mantenendo invariati i fatti di scenario:

- verifica pagamento fallita per duplicate charge;
- lavoro PAY-42 bloccato;
- review sconosciuta;
- prossimo passo: ispezionare le evidenze di retry prima di un'altra review;
- copertura finale `none` e refresh fallito.

Generare nuove catture 1440×900 chiaro e 1024×768 scuro con testo al 130%.
Confrontarle visivamente con la baseline, documentando quali problemi sono stati
corretti. Verificare che causa, lavoro e prossimo passo siano interamente leggibili
e che lo stato finale non suggerisca salute del progetto.

Non usare l'oracle precedente come istruzione per l'osservatore. È consentito
aggiornare l'oracle soltanto se cambia una risposta visibile attesa per effetto del
fix; motivare ogni modifica nel report.

### 8. Rieseguire calibrazione e audit

Prima dell'agente, catturare e ispezionare visivamente tutte le otto fixture. I
quattro controlli corretti devono restare risolvibili e ogni variante difettosa
deve differire dalla corretta per un solo aspetto pertinente.

Eseguire ogni controllo esattamente due volte con la stessa configurazione e senza
retry selettivi. Rieseguire PAY-42 nei due viewport. Registrare modello, reasoning,
versione CLI/Flutter, commit e worktree modificato, prompt/oracle/immagini, hash,
sequenza, token e output grezzi.

Il report Markdown deve includere collegamenti alle immagini e una conclusione
distinta per:

- correttezza funzionale del percorso;
- fedeltà/leggibilità/utilità dell'interfaccia;
- affidabilità misurata del valutatore.

Se la calibrazione resta negativa, dichiararlo senza abbassare aspettative o
modificare i controlli. Raccomandare l'uso del valutatore come gate soltanto se le
metriche osservate lo giustificano; una suite di otto fixture resta comunque una
misura locale, non una stima generale di usabilità.

## Criteri di completamento

- [ ] Copertura `none`, dati mancanti o refresh fallito non producono più copy o
  icone che suggeriscano uno stato sano o l'assenza verificata di problemi.
- [ ] Un lavoro `Blocked` mostra nel dossier causa, identità del lavoro e prossimo
  passo quando fornito, con degradazione onesta quando manca.
- [ ] Ogni attenzione nell'overview identifica esplicitamente il lavoro interessato
  oppure dichiara che l'associazione non è risolvibile.
- [ ] Review `unknown` resta distinta da approvazione, attesa e indisponibilità.
- [ ] I nuovi comportamenti sono coperti da test deterministici, inclusi viewport
  compatto e testo al 130%.
- [ ] Il primo osservatore resta neutrale e tecnicamente separato dall'oracle.
- [ ] Il confronto rileva falsa fedeltà e testo essenziale troncato anche quando la
  risposta testuale superficiale coincide con parole attese.
- [ ] Le quattro coppie sono nuovamente verificate visivamente e hanno due
  esecuzioni complete per controllo, senza selezione dei risultati.
- [ ] Il report mostra corretti riconosciuti, difetti rilevati/mancati, falsi
  allarmi, non valutabili, errori tecnici e limiti del denominatore.
- [ ] PAY-42 produce nuove immagini, osservazioni e confronto tracciabili nei due
  viewport, con spiegazione del prima/dopo.
- [ ] Cattura e test locali funzionano senza modello; errori agentici non vengono
  mascherati come successo.
- [ ] Analisi statica, test pertinenti e suite completa passano; skip o problemi
  preesistenti sono distinti.
- [ ] Documentazione e README descrivono comandi, risultati e limiti aggiornati.
- [ ] Nessun dato reale, modifica estranea, giudizio UX obbligatorio in CI, commit,
  PR o pubblicazione.

## Verifica finale minima

Eseguire almeno:

```sh
dart format --output=none --set-exit-if-changed \
  lib/presentation/project_observatory_page.dart \
  test/project_observatory_resilience_test.dart \
  test/work_item_dossier_test.dart \
  test/agentic_ux_test.dart \
  test/agentic_ux_calibration_test.dart
flutter analyze --no-pub
flutter test --no-pub
python3 -B -m unittest discover -s tests -p 'test_agentic_ux_runner.py'
git diff --check
python3 tests/run-agentic-ux.py --capture-calibration
python3 tests/run-agentic-ux.py --observe --calibrate
```

Se i test del dossier richiedono fixture dal checkout Mana adiacente, aggiungere
fixture sintetiche locali per i nuovi casi; non nascondere dipendenze mancanti con
skip silenziosi. Non ripetere selettivamente una chiamata agentica fallita per
ottenere un verdetto diverso; distinguere un errore tecnico da un risultato valido.

## Consegna

Consegnare:

- elenco dei file modificati e motivazione;
- descrizione del comportamento prima/dopo;
- comandi eseguiti e risultati effettivi;
- collegamenti al report Markdown, JSON, immagini e output grezzi;
- metriche di calibrazione con denominatori espliciti;
- eventuali limiti residui e raccomandazione motivata sull'affidabilità del
  valutatore.

## Testo da passare a Terra come goal

> Implementa integralmente `docs/goal-terra-agentic-ux-fixes.md`. Correggi gli
> stati UX fuorvianti relativi a copertura/refresh, rendi causa e prossimo passo dei
> lavori bloccati visibili e associa esplicitamente ogni attenzione al lavoro.
> Rafforza il valutatore senza contaminarlo con oracle o risposte attese, riesegui
> test, catture, calibrazione e PAY-42 e consegna prove prima/dopo. Preserva il
> worktree esistente e non alterare fixture, soglie o aspettative per ottenere un
> risultato positivo. Prosegui fino a soddisfare tutti i criteri di completamento;
> un esito di calibrazione negativo va misurato e riportato, non mascherato.
