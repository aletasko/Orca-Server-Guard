#!/usr/bin/env bash
set -euo pipefail

[[ $(id -un) == orca ]] || { echo 'Eseguire come utente orca' >&2; exit 1; }
KIT=$HOME/.local/share/orca-server-guard
DROPIN=/etc/systemd/system/orca-serve.service.d/20-orca-server-guard.conf
LEGACY=$HOME/.local/bin/systemd-run
BACKUP=$KIT/legacy-systemd-run.disabled

[[ -f $BACKUP && ! -e $LEGACY ]] || {
  echo 'Backup del vecchio shim assente o destinazione già occupata' >&2
  exit 1
}
[[ -f $DROPIN ]] || { echo 'Drop-in del plugin assente' >&2; exit 1; }
grep -qF '# Managed by Orca Server Guard.' "$DROPIN" || {
  echo 'Il drop-in è stato modificato: non lo rimuovo' >&2
  exit 1
}
sudo -n true
mv "$BACKUP" "$LEGACY"
sudo -n rm "$DROPIN"
sudo -n systemctl daemon-reload
echo 'Ripristinato il vecchio shim. Il servizio non è stato riavviato.'
