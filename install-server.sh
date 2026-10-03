#!/usr/bin/env bash
set -euo pipefail

[[ $(id -un) == orca ]] || { echo 'Installare come utente orca' >&2; exit 1; }
[[ $(hostname -s) == contabo1 ]] || { echo 'Questo plugin è configurato solo per contabo1' >&2; exit 1; }
sudo -n true
systemctl cat orca-serve.service >/dev/null

SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
KIT=$HOME/.local/share/orca-server-guard
DROPIN=/etc/systemd/system/orca-serve.service.d/20-orca-server-guard.conf
LEGACY=$HOME/.local/bin/systemd-run
LEGACY_COPY=$HOME/.local/share/orca-fix-demone/systemd-run

if [[ -e $DROPIN ]]; then
  grep -qF '# Managed by Orca Server Guard.' "$DROPIN" || {
    echo "Drop-in esistente non gestito dal plugin: $DROPIN" >&2
    exit 1
  }
fi

install -d -m 755 "$KIT" "$KIT/bin"
install -m 755 "$SOURCE/systemd-run" "$KIT/bin/systemd-run"
install -m 755 "$SOURCE/guard.sh" "$KIT/guard.sh"
install -m 755 "$SOURCE/restore-legacy.sh" "$KIT/restore-legacy.sh"

temporary=$(mktemp)
trap 'rm -f "$temporary"' EXIT
cat > "$temporary" <<EOF
# Managed by Orca Server Guard.
[Service]
Environment="PATH=$KIT/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
EOF
sudo -n install -m 644 "$temporary" "$DROPIN"
sudo -n systemctl daemon-reload

environment=$(systemctl show orca-serve.service -p Environment --value)
[[ $environment == *"PATH=$KIT/bin:"* ]] || {
  echo 'Il servizio non ha caricato il PATH del plugin' >&2
  exit 1
}
env XDG_RUNTIME_DIR="/run/user/$(id -u)" DBUS_SESSION_BUS_ADDRESS=disabled: \
  "$KIT/bin/systemd-run" --user --scope /bin/true >/dev/null

if [[ ${1:-} == --migrate-legacy && -e $LEGACY ]]; then
  cmp -s "$LEGACY" "$LEGACY_COPY" || {
    echo 'Il vecchio systemd-run non coincide con quello noto: non lo sposto' >&2
    exit 1
  }
  [[ ! -e $KIT/legacy-systemd-run.disabled ]] || {
    echo 'Backup del vecchio shim già presente: non lo sovrascrivo' >&2
    exit 1
  }
  mv "$LEGACY" "$KIT/legacy-systemd-run.disabled"
  echo "Vecchio shim disattivato e salvato in $KIT/legacy-systemd-run.disabled"
fi

echo "Protezione del plugin installata in $KIT"
echo 'Il servizio non è stato riavviato.'
"$KIT/guard.sh" check
