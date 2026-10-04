# Handoff — Native Feedback / desktop-long E2E

Aggiornato il 13 settembre 2026. Checkout: `/Users/zel/projects/mana-familiar`.
Checkpoint iniziale: `025c3c2 feat: verify native draft recovery`.
Checkpoint del profilo lungo committato su richiesta dell'utente il 14 settembre
2026; la verifica nativa finale resta aperta.

## Aggiornamento verificato — 4 ottobre 2026

Le PR di completamento sono Familiar #13 e Mana #16. Familiar usa il protocollo
ufficiale Flutter `AppLifecycleListener.onExitRequested` su Windows e attende il
salvataggio delle bozze; un errore annulla Close e conserva il testo per retry.
Mana pubblica il manifest delle dieci sezioni Story Start e annuncia
`human_feedback` in Inspect solo quando il producer è presente. Activity usa
pagine opzionali da massimo 500 eventi e rifiuta i cursori di revisioni superate.

Verifica locale: 242 test Flutter passati, 7 skip; analyzer senza problemi;
22 regressioni Python passate. Soak producer completato in 3.711,057 secondi,
1.000 create accettate e 3.358 record canonici, in
`build/feedback-audit/run-1791096735-013ea83f2c`. È una prova API, non desktop.

La nuova prova desktop-long macOS
`build/native-feedback-audit/run-1791101833-b87b41fc4e` è **fallita prima delle
azioni**: `osascript is not allowed assistive access (-25211)`. Il consenso
all'automazione è stato ricevuto, ma il permesso OS non è disponibile; nessun
permesso è stato modificato. CUA riesce a leggere la finestra, ma le azioni
Close e tastiera vanno in timeout. Le precedenti prove non chiudono questo gate.

Il runner `tests/run-windows-native-feedback-e2e.py` verifica due sessioni reali,
Close tramite Windows UI Automation prima del debounce, riapertura, isolamento
e assenza delle bozze dal registro canonico. Il composer usa i callback dei
widget montati del bridge debug; questo non certifica input pixel o screen reader.
Gli esiti Windows finali devono essere associati al report effettivo, senza
interpretare un build o la sola apertura del picker come prova di selezione.

## Stato storico — settembre 2026

Nessuna run attiva. Il 13 settembre alle 23:14 la lettura System Events
indica `loginwindow` PID 415; `pmset -g assertions` indica UserIsActive 0.
Le ultime due run smoke (`run-1789333856-127e90c6fe` e
`run-1789333957-a1819294ac`) hanno avviato Dart ma non esposto finestre
entro 90 s. Non rilanciare finché la sessione grafica non è sbloccata.

`run-1789331848-b775d512f8` ha completato 300 azioni in 1.205,221 s,
R1–R5, tre restart e dieci recuperi, ma è fallita nel Quit finale.
Il suo `native/desktop-long.json` passed certifica solo la sequenza interna.
Close/Quit sono stati poi corretti e verificati con smoke e draft-smoke.
La successiva `run-1789333383-80e83f09d9` è fallita al passo 110 nel
controllo focus: PID rilevato 57125 invece di A 27201.

Ultima modifica: i checkpoint delle rigenerazioni e `run_ui_driver` non
attivano più finestre; il bridge warm-up frame completa già build/layout.
Il test Python verifica anche che il driver non invochi focus. Focus resta
nei controlli nativi iniziali/lifecycle. Questa ultima modifica ha 10 test
Python verdi e sintassi Bash verde, ma lo smoke è stato bloccato dall'ambiente
prima delle azioni. Non dichiarare desktop-long verde finché
uno smoke e una run completa sullo stato finale non producono `report.json`
passed. Le prove di rendering pixel e performance restano fuori scope.

## Obiettivo e implementazione

Due Runner macOS reali sullo stesso progetto sintetico: almeno 20 minuti,
300 azioni programmate (75 cicli set/publish commento e reply alternando A/B),
cinque rigenerazioni governate, tre restart B Close/Quit/Close e dieci fault.
Le azioni usano i callback dei widget montati tramite bridge debug loopback;
non sono input Accessibility. Il polling non conta come azione.

Fault dopo cicli completi: conflitti 8/176, bozza 12/256, ritardi 16/280,
ACK 64/204, letture 96/232. Wrapper nel solo progetto sintetico, hook Mana
reali, chmod ricorsivo e ripristino sul solo storage temporaneo delle bozze.
Asserzioni UI e canoniche verificano errore/recupero e assenza di duplicati.

Correzioni emerse nel resume:

- Bash `local` separate prima di usare label, `errtrace`, token `--token=...`.
- Refresh conserva il dettaglio e allinea revisione/payload; reader eager
  montato anche sotto viewport nella vista Advanced. Regressioni widget.
- Bridge: callback 95 s/status 5 s; Runner startup 90 s. Prima di status,
  warm-up frame per build/layout dei widget anche senza vsync nelle finestre
  occluse. Non certifica la consegna dei pixel o prestazioni.
- Nessun focus nei checkpoint reader: bridge layout anche in background.
  Attesa 250 ms e verifica PID realmente in primo piano per lifecycle AppKit.
- Composer verificato prima dell'invio: blocca modifiche esterne al testo
  o autore sintetici invece di pubblicarle.
- Storia `changed` ammessa solo nell'osservazione del conflitto storico,
  senza riclassificarla come `valid` o ammettere missing/ambiguous.
- Close/Quit tramite menu nativi per PID, senza tasti globali. Ricerca Quit
  con indici numerici e click inline: memorizzare l'oggetto AX per nome può
  indirizzare l'altra istanza, entrambe chiamate Mana Familiar. Menu Apple
  può precedere il menu applicazione. Anche bozze pre-debounce verificate.

## Verifiche concluse

- `flutter analyze --no-pub`: verde.
- `flutter test --no-pub`: 207 passed, 4 harness dedicati skipped.
- `flutter build macos --debug --no-pub`: verde.
- `env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests/test_native_feedback_e2e_runner.py`: 10 test verdi.
- Sintassi Bash dei runner e wrapper, `git diff --check`: verdi.
- Smoke finale: `build/native-feedback-audit/run-1789333300-6480ede840/report.json`, passed, 41,171 s.
- Draft-smoke finale: `build/native-feedback-audit/run-1789333348-4874ef056c/report.json`, passed.

## Ripartenza

```sh
python3 tests/run-native-feedback-e2e.py --mana-root /Users/zel/projects/mana --profile desktop-long --skip-build
```

Dopo lo sblocco eseguire prima `--profile smoke --skip-build`, poi
`--profile desktop-long --skip-build`. Leggere le evidenze `native/ui/*.err`,
`native/shell-errors.log`, `failure.json`, `manifest.json` o `report.json`.
Conservare fallimenti e rerun in directory distinte. Non riusare il passed
interno di una run fallita come report finale. Dopo la run verde aggiornare
README e piano e verificare diff. Committare gli aggiornamenti successivi nel
solo Familiar. Nessun push richiesto.

Non modificare/stagiare il checkout esterno `/Users/zel/projects/mana`, già
dirty prima del lavoro; fixture soltanto lette/eseguite. Preferenze reali
intatte: ogni run ha una root e sessioni temporanee. Evidenze ignorate in
`build/native-feedback-audit/`; cleanup dei soli PID creati dal runner.

## Fuori da questo incremento

Windows, soak 60 minuti, metriche performance in build profile, decisione →
rigenerazione governata integrata, bozze reply/decisione tra progetti e
storia UI completa changed/missing/ambiguous restano aperti.
