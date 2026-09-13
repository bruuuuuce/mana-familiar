# Valutazione UX agentica

Questo harness produce prove sintetiche per PAY-42 e distingue tre risultati:
il percorso Flutter deterministico, ciò che un osservatore legge nei pixel, e la
calibrazione di quell’osservatore su controlli costruiti apposta. Un risultato
positivo del primo non rende positivi gli altri due.

## Comandi riproducibili

La cattura non richiede un modello né usa token:

```sh
python3 tests/run-agentic-ux.py
```

Per catturare anche i controlli senza un modello (e ispezionarne visivamente le
PNG prima dell’uso):

```sh
python3 tests/run-agentic-ux.py --capture-calibration
```

Per eseguire esplicitamente l’osservatore sui due viewport PAY-42:

```sh
python3 tests/run-agentic-ux.py --observe
```

Per catturare e far osservare due volte ciascuno degli otto controlli (quattro
coppie corretto/difettoso), insieme a PAY-42:

```sh
python3 tests/run-agentic-ux.py --observe --calibrate
```

`--observe` e `--calibrate` richiedono una CLI Codex autenticata e consumano token.
Il runner inoltra solo `CODEX_MODEL` e `CODEX_REASONING_EFFORT` impostati
esplicitamente, registra configurazione richiesta e quella riportata dalla CLI, e
non cambia il modello. Non eseguire selettivamente lo stesso caso finché passa:
ogni controllo è eseguito esattamente due volte e tutti i risultati restano nel
report.

## Contratti e isolamento

`test/agentic_ux_test.dart` genera immagini e un manifest sorgente; il runner copia
in una directory temporanea dell’osservatore solo immagini rinominate opacamente
(`frame-01.png`), checkpoint opachi (`c01`) e domande neutre. L’oracle generato dal
test, i report precedenti, il checkout e il codice non sono nella directory di
lavoro read-only della CLI. Il prompt non contiene fatti PAY-42 o classificazioni
attese. Questo è un confine tecnico utile, non una garanzia assoluta contro
conoscenza pregressa del modello o contenuto testuale visibile dentro l’immagine.

L’output immutabile dell’osservatore è versionato (`2.0`) e contiene risposta,
evidenza/localizzazione, certezza, finding attribuiti all’osservatore e campi
canonici letti nei pixel (`status`, `identity`, `cause`, `action`). La fedeltà ai
dati del producer è calcolata dal confronto locale soltanto dopo l’output grezzo.
Il contratto distingue leggibilità del segmento essenziale (posizione e
completezza), risposta al compito e azionabilità; `not_applicable` è valido per
una domanda di sola lettura. Il validatore controlla forma, completezza,
checkpoint duplicati e riferimenti inventati, non la verità dei pixel.

## Controlli di calibrazione

`test/agentic_ux_calibration_test.dart` renderizza composizioni Material di test,
non PNG ritoccati e non UI di produzione. Le coppie variano rispettivamente:
copertura dati, stato review, associazione problema-lavoro e leggibilità dell’azione
essenziale. Le varianti difettose esistono soltanto nel test. Ispezionare le PNG
nel report prima di interpretare la calibrazione: la suite misura solo questi otto
casi sintetici, non una stima generalizzabile dell’usabilità.

Ogni directory `build/ux-audit/run-*` contiene PNG, log Flutter, manifest/oracle,
bundle opaco realmente consegnato al modello, output grezzo, hash/snapshot di
immagini, prompt e oracle, piano di esecuzione ed eventi con PID e ordine reale.
Il report conserva unità checkpoint × controllo × ripetizione: controlli corretti,
finding osservati, violazioni stabilite dal confronto, metrica «almeno major»,
falsi allarmi, non valutabili, errori tecnici e disaccordi di gravità. Un errore
CLI/modello, timeout, input o report incompleto scrive il report parziale e termina
con codice 2. `--render-report` produce un derivato timestampato senza sovrascrivere
l’evidenza. Il giudizio UX rimane informativo: non è richiesto dalla CI.

Un `not_determinable` resta nel denominatore e impedisce un pass positivo. Nessuna
media compensa un checkpoint grave: risposta errata, fedeltà/leggibilità incoerente
o difetto intenzionale non segnalato rendono fallita quell’osservazione. Il runner
crea una nuova directory per ogni esecuzione e rifiuta di riusare un output
dell’osservatore preesistente.

## Risultato locale storico

L’esecuzione completa del 9 settembre 2026 è disponibile localmente in
`build/ux-audit/run-nx5q5mro/`: PAY-42 ha completato 8/8 checkpoint nei due
viewport, senza errori tecnici. Le otto fixture di calibrazione sono state prima
catturate e ispezionate visivamente, poi osservate due volte ciascuna (16
osservazioni). Con `gpt-5.6-terra`, reasoning `high`, il valutatore ha riconosciuto
6/8 controlli corretti, rilevato 5/8 difetti intenzionali, mancato 3/8 e restituito
3/16 risposte non valutabili; non sono emersi falsi allarmi. I log, output grezzi,
hash, sessioni, sequenza e token registrati restano nel `report.json` locale.

Questa calibrazione storica usa il contratto precedente e non è confrontabile come
nuova misura con il contratto 2.0; non vengono inventati campi strutturati assenti.
Questa calibrazione è negativa per un uso come gate: il valutatore resta soltanto
un segnale informativo. Le verifiche deterministiche e l’ispezione dei frame PAY-42
mostrano invece il comportamento corretto dell’interfaccia dopo il fix: il refresh
fallito non suggerisce salute, l’overview nomina il lavoro, e il dossier mostra
causa e prossimo passo del blocco.

## Esecuzione 2.0

La nuova esecuzione locale è in
[`run-ip3w8uag`](../build/ux-audit/run-ip3w8uag/), con il
[report ricalcolato](../build/ux-audit/run-ip3w8uag/report-recomputed-20260909T204321Z.md).
Ha conservato 18 chiamate pianificate (PAY-42 nei due viewport e due osservazioni
per ciascuno degli otto controlli), 67.866 token, configurazione effettiva
`gpt-5.6-terra`/`high`, output grezzi, eventi e hash. Il confronto registra 4
riconoscimenti corretti su 16 unità di calibrazione, 8 violazioni intenzionali
stabilite dal confronto, 3 finding mancati, 0 falsi allarmi, 1 disaccordo di
gravità e 3 risposte incerte. È quindi esplicitamente inadeguato come gate.

I due viewport PAY-42 hanno completato le catture funzionali (otto unità), ma il
valutatore non ha riconosciuto tutti i campi canonici: questo è un limite del
valutatore, non un cambiamento del risultato Flutter. Il report conserva la
distinzione e non deduce verità del producer dai pixel.

Confronto visivo (baseline disponibile `run-nx5q5mro`, stessa navigazione
scriptata):

- Chiaro 1440×900: [overview prima](../build/ux-audit/run-nx5q5mro/desktop-light-overview.png) / [dopo](../build/ux-audit/run-ip3w8uag/desktop-light-overview.png), [dossier prima](../build/ux-audit/run-nx5q5mro/desktop-light-work.png) / [dopo](../build/ux-audit/run-ip3w8uag/desktop-light-work.png), [review prima](../build/ux-audit/run-nx5q5mro/desktop-light-review.png) / [dopo](../build/ux-audit/run-ip3w8uag/desktop-light-review.png), [refresh prima](../build/ux-audit/run-nx5q5mro/desktop-light-unavailable.png) / [dopo](../build/ux-audit/run-ip3w8uag/desktop-light-unavailable.png).
- Scuro 1024×768, testo 130%: [overview prima](../build/ux-audit/run-nx5q5mro/compact-dark-overview.png) / [dopo](../build/ux-audit/run-ip3w8uag/compact-dark-overview.png), [dossier prima](../build/ux-audit/run-nx5q5mro/compact-dark-work.png) / [dopo](../build/ux-audit/run-ip3w8uag/compact-dark-work.png), [review prima](../build/ux-audit/run-nx5q5mro/compact-dark-review.png) / [dopo](../build/ux-audit/run-ip3w8uag/compact-dark-review.png), [refresh prima](../build/ux-audit/run-nx5q5mro/compact-dark-unavailable.png) / [dopo](../build/ux-audit/run-ip3w8uag/compact-dark-unavailable.png).

## Limiti

Le schermate sono dati sintetici da widget Flutter con navigazione scriptata; non
sono esplorazione autonoma del desktop né copertura dell’intera applicazione. Non
coprono trasporto CLI reale, chrome o dialoghi nativi, documenti, cataloghi grandi,
tastiera, screen reader o validazione con persone. Non modificare la UI di
produzione per migliorare questi controlli.

Verifiche locali del runner:

```sh
python3 -B -m unittest discover -s tests -p 'test_agentic_ux_runner.py'
dart format --output=none --set-exit-if-changed test/agentic_ux_test.dart test/agentic_ux_calibration_test.dart
flutter analyze --no-pub
flutter test --no-pub
git diff --check
```
