# Orca Server Guard

Plugin locale basato sull'esempio ufficiale `hello-orca`. Il pannello invia
`check`, `restart` o `result` a una scheda shell scelta dall'utente. Usa solo
le capacità `workspace:read` e `terminal:send` dell'API plugin v1.

Il correttivo che protegge il demone è `/home/orca/.local/bin/systemd-run`.
Questo plugin non sostituisce quel file né può intervenire mentre Orca è spento.
Lo script sul server controlla che il demone sia già in uno scope separato prima
di avviare un riavvio. Il worker di riavvio gira in una unità systemd separata,
così può confrontare le schede e i PID Claude anche se la connessione si interrompe.

## Installazione su contabo1

```sh
install -m 755 server-guard.sh /home/orca/.local/share/orca-fix-demone/orca-server-guard.sh
/home/orca/.local/share/orca-fix-demone/orca-server-guard.sh check
```

Nel client Orca, aprire **Settings → Plugins → Install plugin → Git URL** e
inserire `https://github.com/aletasko/Orca-Server-Guard.git#main`.
Il repository è pubblico. Approvare le due capacità richieste.
Il pannello
opera su una shell nel worktree selezionato: scegliere una scheda shell su
contabo1, mai una chat agente. Orca espone al plugin solo gli ID dei terminali;
il pannello non può riconoscere il tipo di terminale o leggere l'output.

Nella versione Orca 1.4.212, l'installazione da Git copia una revisione del
repository. Dopo un nuovo push su `main`, ripetere l'installazione dallo stesso
Git URL per aggiornare il plugin. Orca non applica automaticamente i nuovi commit.

Il comando `restart` registra l'esito in
`~/.local/share/orca-fix-demone/restarts/<data>/result.log`; `result` stampa
l'ultimo esito. Le prove già fatte mostrano che un riavvio conserva le sessioni
del demone attuale. Dopo un aggiornamento va verificato anche il primo avvio di
un demone nuovo: l'API plugin non garantisce compatibilità tra versioni.

Per togliere il correttivo systemd usare
`~/.local/share/orca-fix-demone/annulla.sh`. Disinstallare il plugin dal client
non modifica il server.
