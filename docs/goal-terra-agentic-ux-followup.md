# Piano per Terra: chiudere le lacune residue della verifica UX

## Obiettivo e ambito

Implementare i punti seguenti nel repository `/Users/zel/projects/mana-familiar`.
Il piano deriva dalla lettura del worktree e degli output grezzi del 9 settembre
2026, successiva a `goal-terra-agentic-ux-fixes.md`. La precedente dichiarazione
di completamento era troppo ampia: diversi criteri non sono ancora dimostrati.
Questo documento descrive lavoro da eseguire, non correzioni già implementate.

Preservare le modifiche non committate. Usare dati sintetici, mantenere i test
locali senza modello, non pubblicare né creare commit/PR. Modificare la produzione
solo per i problemi circoscritti qui descritti. Non cambiare modello o soglie per
ottenere risultati migliori. Il valutatore resta informativo e facoltativo in CI.

## Evidenze e interpretazione corretta della baseline

- Report: [Markdown](../build/ux-audit/run-nx5q5mro/report.md) e
  [JSON](../build/ux-audit/run-nx5q5mro/report.json).
- Catture preliminari: `build/ux-audit/run-3weivzoc/`.
- Prima dei fix: `build/ux-audit/run-ghhtrhoj/`.
- Modello effettivo nei log: `gpt-5.6-terra`, reasoning `high`;
  CLI `0.153.4`, Flutter `3.44.8`. Il report registra 197535 token per 18 chiamate.
- Ultima verifica registrata nella conversazione: 175 test Flutter passati,
  4 skip di integrazioni con harness dedicati, 12 test Python passati e analisi
  statica pulita. Rieseguire le verifiche prima della consegna.
- Il report conta 6/8 controlli corretti riconosciuti, 5/8 difetti rilevati,
  3/8 mancati, 3/16 risposte non valutabili. Sono risultati dell'algoritmo attuale,
  non una misura già validata dell'affidabilità del modello.

I file sotto `build/` sono locali e ignorati da Git. Se mancano, dichiararlo:
non ricostruire osservazioni storiche come se fossero output originali.

| Evidenza | Problema accertato | Conseguenza |
| --- | --- | --- |
| `control-04-run1/2.observation.json` | Il modello legge correttamente `approved`; l'immagine non rivela che il producer era `unknown` | La falsità rispetto ai dati è verificabile nel secondo passaggio, non deducibile dai soli pixel |
| `control-08-run1.observation.json` | `readability=partially_visible` e finding `minor` sul taglio | Il report lo conta come difetto mancato e dichiara zero disaccordi di gravità: confonde rilevazione e severità |
| `control-07-run2.observation.json` | Risposta italiana corretta: «Ispezionare le prove del tentativo prima di un’altra revisione» | Il confronto cerca `inspect` o `retry` e boccia la risposta |
| `control-01-run1.observation.json` | Risposta corretta sulla salute non determinabile; `task_usefulness=not_usable` | Il contratto confonde capacità di rispondere e presenza di un'azione interattiva |
| `compare_observation()` | Un falso allarme non entra in `passed`; gravità/errori tecnici sono costanti zero | Un report può essere positivo pur avendo un finding grave infondato |
| `agent_execution_metadata()` | La sequenza è ricavata ordinando alfabeticamente i log | La sequenza dichiarata non è quella delle chiamate |

I fix della UI già presenti separano gli stati di copertura nell'overview,
esplicitano il lavoro nella riga di attenzione e mostrano causa/azione nel dossier
PAY-42. Preservarli. I controlli difettosi di calibrazione sono composizioni di test:
non dimostrano che la produzione mostri review falsamente approvate o azioni tagliate.

## 1. P0 — Correggere il contratto osservazione/oracle/confronto

File: `tests/run-agentic-ux.py`, `tests/ux-review-prompt.md`,
`test/agentic_ux_calibration_test.dart`, `test/agentic_ux_test.dart`.

1. Versionare schema osservatore, oracle e confronto. Separare esplicitamente:
   fatto letto nei pixel, contraddizione interna visibile, fedeltà rispetto ai
   dati producer (solo secondo passaggio), leggibilità, risposta al compito e
   azionabilità quando pertinente.
2. Per la review, estrarre uno stato strutturato generale; confrontare `approved`
   osservato con `unknown` nell'oracle. Il secondo passaggio deve produrre una
   violazione di fedeltà anche senza finding spontaneo. Non chiedere al primo
   osservatore di conoscere dati nascosti; attribuire ogni finding al passaggio
   che lo ha prodotto.
3. Sostituire `any(token in answer)` come prova sufficiente di correttezza.
   Definire campi canonici generali per stato, identità, causa e azione, con
   validazione separata del testo libero. Supportare risposte italiane e inglesi;
   aggiungere casi di negazione e risposte che citano un token ma affermano il
   contrario. Non risolvere aggiungendo soltanto la frase storica agli alias.
4. Richiedere una valutazione di leggibilità riferita al segmento essenziale,
   alla sua posizione e alla completezza. La ricostruzione semantica di testo
   tagliato non rende il testo completamente leggibile.
5. Distinguere `answerability` da `actionability`, con `not_applicable` quando
   il checkpoint chiede solo una lettura. Un'informazione onesta di indisponibilità
   può rispondere correttamente al compito.
6. Trattare `not_determinable` come dato esplicito: può essere la risposta attesa
   sulla salute del progetto; è diverso dall'impossibilità del valutatore di
   giudicare i pixel. Entrambi restano nel rispettivo denominatore.

Accettazione: test locali dimostrano falsa approval rilevata dal confronto,
traduzione corretta accettata, negazione respinta, testo tagliato riconosciuto
come difetto indipendentemente dalla risposta indovinata. Nessuna risposta attesa
o classificazione di fixture entra nel prompt/schema del primo osservatore.

## 2. P0 — Rendere coerenti metriche, gravità e verdetti

File: runner e `tests/test_agentic_ux_runner.py`.

- Definire prima delle nuove chiamate l'unità di conteggio: checkpoint × controllo
  × ripetizione. Deduplicare finding sullo stesso difetto; conservare i dettagli.
- Separare difetto osservato, difetto rilevato dal confronto e accordo sulla
  gravità. Un taglio riconosciuto come `minor`, dove l'oracle richiede `major`,
  produce un disaccordo di gravità senza cancellarne la rilevazione. Mantenere
  anche la metrica storica «rilevato almeno major» per confrontabilità.
- Contare i falsi allarmi anche quando non sono formulati come finding ma come
  valutazioni strutturate errate, con regole esplicite per evitare doppio conteggio.
- Un falso allarme grave impedisce il riconoscimento del controllo corretto e
  il relativo pass. Nessuna media compensa una violazione grave.
- Calcolare davvero `severity_disagreements` e `technical_errors`; zero è ammesso
  solo se dimostrato, altrimenti usare stato non misurato/incompleto.
- Calcolare denominatori dinamici, per coppia, variante e ripetizione. Rimuovere
  `/8`, `/16` e conclusioni negative prefissate dai report parziali o senza calibrazione.
- Non chiamare «deterministic checkpoint comparisons» i giudizi agentici PAY-42.
  Derivare l'esito funzionale dall'esecuzione Flutter e la valutazione UX dal
  confronto: evitare `N/N` costruito dal solo numero di checkpoint presenti.

Accettazione: coprire casi solo PAY-42, sola calibrazione, report incompleto,
finding duplicati, falso allarme grave con risposta corretta, minor/major,
incertezza legittima e incertezza dell'osservatore. Documentare le formule.

## 3. P0 — Completare isolamento, gestione errori e tracciabilità

- Il bundle attuale contiene solo file consentiti, ma `cwd` e sandbox read-only
  non provano che l'oracle fuori dalla directory sia illeggibile. Verificare le
  capacità effettive del processo osservatore; implementare un confine che
  impedisca letture dell'oracle/codice e tool non necessari. Verificare con una
  sentinella sintetica fuori dal bundle. Non dichiarare isolamento tecnico sulla
  base della sola istruzione «non usare strumenti».
- Rendere opachi anche i nomi delle directory consegnate al processo: oggi il
  percorso include `control-04-run1` o `desktop-light`.
- Registrare un piano di esecuzione prima delle chiamate, con ID opachi,
  sequenza reale, timestamp, configurazione richiesta ed effettiva, esiti e PID
  o handle quando disponibili. Non ricostruire ordine o successo dall'alfabeto.
- Conservare snapshot/hash di prompt, schema, oracle, immagini, codice modificato
  e output grezzi. Lo stato Git «dirty» non identifica il contenuto del worktree.
- Le variabili modello/reasoning oggi sono annotate senza essere inoltrate dal
  runner: definire configurazione supportata, senza cambi silenziosi, e verificare
  che ogni chiamata abbia usato la stessa configurazione effettiva.
- Scrivere risultati parziali e report anche in caso di errore modello, JSON
  malformato, timeout, checkpoint mancante o interruzione. Exit code 2 per audit
  tecnicamente incompleto; i giudizi UX negativi restano informativi.
- Dopo timeout gestire e verificare la terminazione dei processi figli. Non
  riavviare su semplice scadenza di osservazione di un processo ancora vivo.
- Non ripetere singole chiamate per migliorare un risultato. Pianificare due
  tentativi per controllo; una nuova esecuzione dopo errore tecnico deve avere
  identità distinta, conservando quella incompleta e la motivazione.
- Rendere `--render-report` validante e non distruttivo: validare completezza e
  riferimenti, generare un nuovo report derivato/versionato; non sovrascrivere
  l'evidenza storica. Token mancanti vanno dichiarati come mancanti, non come zero.

Accettazione: test con processo/CLI fittizio dimostrano exit code 2, report
parziali, output malformato/mancante, nessun riuso, hash stabili e sequenza reale.
Testare il comando di ingresso oltre alle singole funzioni. La cattura deve
funzionare senza autenticazione/modello.

## 4. P1 — Completare dossier e resilienza della UI

File: `lib/presentation/project_observatory_page.dart`, test locali dedicati.

- `_work()` usa il dettaglio per gli artefatti della sezione, ma il riquadro del
  blocco usa solo `selected.attentionItems` del sommario. Gestire gli attention
  item presenti nel dettaglio, con precedenza esplicita, identità verificata e
  assenza distinta da dettaglio non ancora caricato. Non unire alla cieca dati
  di revisioni diverse.
- I link del riquadro cercano solo `item.artifacts`; `_artifact()` non cerca
  gli artefatti nelle sezioni del dettaglio. Rendere navigabili i riferimenti
  validi disponibili solo nel dettaglio, preservando proprietà e sezione.
- `_refresh()` non invalida `_workDetails`; `_loadWorkDetailIfNeeded()` conserva
  le risposte e ignora gli errori. Riprodurre aggiornamento e risposta tardiva,
  poi garantire coerenza di revisione, fallback stale e errore visibile pertinente.
- Il ramo di refresh che solleva eccezione assegna `_error`, e `build()` sostituisce
  il contenuto con la pagina di errore anche se `_model` esiste; il callback
  `onRefresh` è fuori dal `try`. Coprire questi percorsi con client sintetico e
  preservare i dati utili marcandoli stale. Verificare il recupero al refresh successivo.
- Evitare il titolo «Nothing reported for overview» immediatamente sotto cause
  già mostrate: specificare che mancano documenti, senza negare il contenuto presente.
- Mantenere distinti review unknown e indisponibilità; verificare copy, badge,
  colore e icona, non soltanto assenza della parola `Approved`.

Accettazione: fixture locali senza checkout Mana adiacente, blocked con dettaglio
più ricco del sommario, più cause di diversa severità, nextAction assente, link
solo nel dettaglio e riferimento irrisolvibile, refresh fallito/recuperato e
risposta tardiva. Matrice completa/partial/none/dati assenti, con/senza attenzione
e refresh fallito. Layout 1024×768 al 130%: verificare testo effettivamente
visibile e interazioni, oltre a presenza di widget e assenza di overflow.

## 5. P1 — Rafforzare scenario e nuova verifica visiva

- Conservare i fatti PAY-42: duplicate charge, blocked, review unknown,
  ispezione delle evidenze retry prima di altra review, copertura finale none
  e refresh fallito.
- L'oracle attuale del dossier controlla solo `blocked`, e quello dell'overview
  accetta un singolo token tra lavoro/causa. Verificare distintamente identità,
  causa e intero prossimo passo nei due viewport. Registrare ogni modifica
  dell'oracle con motivazione e versione.
- Catturare 1440×900 chiaro e 1024×768 scuro al 130%; confrontare visivamente con
  la baseline e allegare coppie prima/dopo nel report, indicando eventuali
  immagini storiche mancanti. Verificare anche i link e il recupero dal refresh.
- Ispezionare tutte le otto fixture di calibrazione prima delle nuove chiamate.
  Collegare l'ispezione agli hash esatti poi consegnati al modello; il runner
  oggi ricattura le fixture senza collegamento all'ispezione preliminare.
- Preservare le quattro coppie esistenti. La coppia identità modifica anche
  numero e disposizione delle card: documentare questo limite senza dichiarare
  una variazione visiva singola perfettamente controllata. Eventuali controlli
  aggiuntivi più isolati vanno versionati, mantenendo i risultati storici.
- Eseguire esattamente due osservazioni per controllo con stessa configurazione,
  e PAY-42 nei due viewport. Nessun retry selettivo o modifica successiva delle
  regole di conteggio per migliorare i punteggi.
- Prima del nuovo modello, ricalcolare gli output storici con il nuovo confronto
  in un artefatto separato. Spiegare differenze attribuibili al validatore,
  separandole da miglioramenti osservati in nuove chiamate. Non inventare campi
  strutturati assenti negli output storici.

## Ordine, verifiche e consegna

Eseguire 1–3 (contratto e prove del runner), poi 4 (UI), infine 5 e documentazione.
Usare i test prima dei fix per riprodurre i problemi. Comandi minimi:

```sh
python3 -B -m unittest discover -s tests -p 'test_agentic_ux_runner.py'
dart format --output=none --set-exit-if-changed lib/presentation/project_observatory_page.dart test/project_observatory_resilience_test.dart test/work_item_dossier_test.dart test/observatory_attention_ux_test.dart test/agentic_ux_test.dart test/agentic_ux_calibration_test.dart
flutter analyze --no-pub
flutter test --no-pub
git diff --check
python3 tests/run-agentic-ux.py --capture-calibration
# Dopo l'ispezione degli input esatti; documentare eventuali nuove opzioni.
python3 tests/run-agentic-ux.py --observe --calibrate
```

Aggiornare `docs/agentic-ux-testing.md` e README. Consegnare un report con file
modificati, prove per ogni punto, risultati e skip effettivi, collegamenti a
immagini/raw output/oracle/hash, errori tecnici e limiti residui. Tenere distinti
esito funzionale, comunicazione della UI e calibrazione del valutatore.

Il piano è concluso quando ogni punto dispone di evidenza verificabile e le
metriche sono coerenti con gli output. Una calibrazione ancora negativa è
accettabile se spiegata correttamente; nessuna promessa che il modello possa
inferire verità nascoste dai pixel. Non dichiarare completamento basandosi sui
soli test verdi o sulla presenza di un report.

## Testo da passare a Terra

> Implementa `docs/goal-terra-agentic-ux-followup.md`. Parti dal worktree attuale,
> preserva i fix esistenti e riproduci le lacune indicate con test sintetici.
> Correggi contratto, metriche, isolamento, tracciabilità e percorsi residui del
> dossier/refresh; poi produci nuove catture, confronto prima/dopo e calibrazione
> completa. Conserva gli output storici e distingue difetti del valutatore,
> del confronto e della produzione. Non cambiare modello, soglie o controlli per
> migliorare artificialmente i risultati. Consegna prove per ogni requisito,
> senza commit, PR o pubblicazioni.
