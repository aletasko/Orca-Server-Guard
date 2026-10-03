# Orca Server Guard

Plugin per contabo1. Il pannello installa e gestisce i propri componenti sul
server attraverso una scheda shell selezionata dall'utente. Usa le capacità
`workspace:read` e `terminal:send` dell'API plugin v1.

Orca esegue il pannello sul client. Quando `orca-serve` è spento il pannello
non può agire: per conservare il demone durante un riavvio servono uno shim
`systemd-run` e uno script persistenti **sul server**. Sono inclusi nel
repository, installati dal pulsante **Installa protezione** e conservati in
`/home/orca/.local/share/orca-server-guard/`. L'installer aggiunge al servizio
`orca-serve` un drop-in systemd che mette lo shim del plugin all'inizio del
`PATH`; non cambia il binario Orca e non riavvia il servizio.

## Installazione

In Orca apri **Settings → Plugins → Install plugin → Git URL** e inserisci:

```text
https://github.com/aletasko/Orca-Server-Guard.git#v0.2.2
```

Approva le capacità richieste. Apri il pannello **Orca Server Guard** in un
worktree su contabo1, crea una scheda **shell** dedicata, premi **Aggiorna
schede** e selezionala. Orca espone al plugin solo gli ID dei terminali: il
pannello non può riconoscere una shell o leggere l'output. Controlla la scheda
scelta prima di inviare comandi.

Premi **Installa protezione** e leggi l'esito nella shell. Il pulsante scarica
la versione `v0.2.2` del repository e installa i componenti sul server. Se il
vecchio shim verificato è presente in `~/.local/bin/systemd-run`, l'installer
lo sposta in `~/.local/share/orca-server-guard/legacy-systemd-run.disabled`;
da quel momento il servizio userà lo shim del plugin al prossimo avvio.

Premi **Verifica** prima di **Riavvia e confronta**. Il controllo richiede che
il demone corrente sia già in uno scope separato. Il riavvio richiede almeno
1 GiB di spazio libero, poi registra il
confronto di schede e processi Claude in
`~/.local/share/orca-server-guard/restarts/<data>/result.log`.
**Ultimo esito** stampa il log nella shell scelta.

I futuri commit non aggiornano automaticamente il plugin installato da Git:
reinstalla dal nuovo tag per aggiornare il pannello, poi premi di nuovo
**Installa protezione** per aggiornare i componenti sul server.

## Ripristino

Se occorre tornare al vecchio shim, esegui sul server:

```sh
bash /home/orca/.local/share/orca-server-guard/restore-legacy.sh
```

Il ripristino non riavvia il servizio. Disinstallare il plugin dal client non
rimuove i componenti sul server, perché devono restare disponibili durante
un riavvio. Il primo avvio di un **nuovo** demone dopo un aggiornamento Orca
resta da verificare senza interrompere le sessioni esistenti.
