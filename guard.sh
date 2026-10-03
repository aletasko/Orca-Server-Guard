#!/usr/bin/env bash
set -euo pipefail

KIT=/home/orca/.local/share/orca-server-guard
CLI=/home/orca/.local/bin/orca-ide
SELF=$KIT/guard.sh
SHIM=$KIT/bin/systemd-run
SERVICE=orca-serve.service

as_orca() {
  if [[ $(id -un) == orca ]]; then
    "$CLI" "$@"
  else
    sudo -n -u orca "$CLI" "$@"
  fi
}

daemon_pid() {
  local pids
  pids=$(pgrep -u orca -f '^/opt/orca/squashfs-root/orca-ide .*/daemon-entry\.js' || true)
  if [[ $(wc -w <<<"$pids") -ne 1 ]]; then
    echo "Atteso un solo demone Orca; trovati: ${pids:-nessuno}" >&2
    return 1
  fi
  printf '%s\n' "$pids"
}

check() {
  local pid scope state path
  state=$(systemctl is-active "$SERVICE")
  [[ $state == active ]] || { echo "Servizio non attivo: $state" >&2; return 1; }
  [[ -x $CLI ]] || { echo "CLI assente: $CLI" >&2; return 1; }
  [[ -x $SHIM ]] || { echo "Correttivo del plugin assente: $SHIM" >&2; return 1; }
  path=$(systemctl show "$SERVICE" -p Environment --value)
  [[ $path == *"PATH=$KIT/bin:"* ]] || { echo 'Il servizio non cerca il correttivo del plugin nel PATH' >&2; return 1; }
  env XDG_RUNTIME_DIR="/run/user/$(id -u orca)" DBUS_SESSION_BUS_ADDRESS=disabled: \
    "$SHIM" --user --scope /bin/true >/dev/null || {
      echo 'Il correttivo del plugin non riesce a creare uno scope utente' >&2
      return 1
    }
  pid=$(daemon_pid)
  scope=$(<"/proc/$pid/cgroup")
  [[ $scope != *"$SERVICE"* ]] || { echo "Demone dentro $SERVICE: riavvio bloccato" >&2; return 1; }
  [[ $scope == *'.scope'* ]] || { echo "Demone fuori da uno scope separato: $scope" >&2; return 1; }
  local terminal_json count
  terminal_json=$(as_orca terminal list --json)
  count=$(python3 -c 'import json,sys; j=json.load(sys.stdin); assert j["ok"]; print(len(j["result"]["terminals"]))' <<<"$terminal_json")
  echo "Servizio: $state, PID $(systemctl show "$SERVICE" -p MainPID --value)"
  local current_path current_pid
  current_pid=$(systemctl show "$SERVICE" -p MainPID --value)
  current_path=$(tr '\0' '\n' <"/proc/$current_pid/environ" | sed -n 's/^PATH=//p')
  if [[ $current_path != "$KIT/bin:"* ]]; then
    echo 'Il processo del servizio userà il PATH del plugin dal prossimo riavvio.'
  fi
  echo "Demone: PID $pid, $scope"
  echo "Schede raggiungibili: $count"
  echo "Processi Claude: $(pgrep -u orca -x claude | wc -l || true)"
  echo 'Controllo superato. Il primo avvio di un demone nuovo resta da verificare dopo un aggiornamento.'
}

restart() {
  check
  local run stamp pid available_kib
  available_kib=$(df -Pk "$KIT" | awk 'NR == 2 { print $4 }')
  if [[ ! $available_kib =~ ^[0-9]+$ || $available_kib -lt 1048576 ]]; then
    echo "Spazio insufficiente per un riavvio verificato: ${available_kib:-sconosciuto} KiB liberi, minimo 1048576 KiB" >&2
    return 1
  fi
  stamp=$(date +%Y%m%d-%H%M%S)
  run=$KIT/restarts/$stamp
  mkdir -m 700 -p "$run"
  pid=$(daemon_pid)
  as_orca terminal list --json >"$run/before.json"
  pgrep -u orca -x claude >"$run/claude-before.txt" || true
  printf '%s\n' "$pid" >"$run/daemon-pid.txt"
  systemctl show "$SERVICE" -p MainPID --value >"$run/server-pid.txt"
  sudo -n /usr/bin/systemd-run --unit="orca-server-guard-$stamp" --collect --no-block /bin/bash "$SELF" worker "$run"
  printf '%s\n' "$run" >"$KIT/last-run"
  echo "Riavvio avviato fuori dal servizio. Esito: $run/result.log"
  echo "Per leggerlo: $SELF result"
}

worker() {
  [[ $(id -u) -eq 0 ]] || { echo 'Il worker richiede root' >&2; return 1; }
  local run=${1:?percorso della prova richiesto}
  [[ $run == "$KIT/restarts/"* && -d $run ]] || { echo 'Percorso della prova non valido' >&2; return 1; }
  GUARD_RUN=$run
  exec >"$run/result.log" 2>&1
  trap 'chown -R orca:orca "$GUARD_RUN"' EXIT
  trap 'echo "ESITO: FALLITO (errore alla riga $LINENO)"' ERR
  echo "Riavvio: $(date -Is)"
  systemctl restart "$SERVICE"
  local ready=0
  for ((i=1; i<=60; i++)); do
    if as_orca status --json 2>/dev/null | python3 -c 'import json,sys; j=json.load(sys.stdin); assert j["ok"] and j["result"]["runtime"]["reachable"]' 2>/dev/null; then
      ready=1
      break
    fi
    sleep 2
  done
  [[ $ready == 1 ]] || { echo 'FALLITO: Orca non raggiungibile entro 120 secondi'; return 1; }
  sleep 5
  as_orca terminal list --json >"$run/after.json"
  pgrep -u orca -x claude >"$run/claude-after.txt" || true
  systemctl show "$SERVICE" -p MainPID --value >"$run/server-pid-after.txt"
  python3 - "$run" <<'PY'
import json, pathlib, sys
run = pathlib.Path(sys.argv[1])
before = json.loads((run / 'before.json').read_text())['result']['terminals']
after = json.loads((run / 'after.json').read_text())['result']['terminals']
before_ids = {t['ptyId'] for t in before}
after_ids = {t['ptyId'] for t in after}
missing = sorted(before_ids - after_ids)
disconnected = [t['ptyId'] for t in after if t['ptyId'] in before_ids and not t.get('connected')]
old_claude = set((run / 'claude-before.txt').read_text().split())
new_claude = set((run / 'claude-after.txt').read_text().split())
lost_claude = sorted(old_claude - new_claude)
daemon_pid = (run / 'daemon-pid.txt').read_text().strip()
daemon_alive = pathlib.Path('/proc', daemon_pid).exists()
daemon_scope = pathlib.Path('/proc', daemon_pid, 'cgroup').read_text().strip() if daemon_alive else ''
server_pid = (run / 'server-pid-after.txt').read_text().strip()
server_env = pathlib.Path('/proc', server_pid, 'environ').read_bytes().split(b'\0')
server_path = next((v[5:].decode() for v in server_env if v.startswith(b'PATH=')), '')
plugin_path_active = server_path.startswith('/home/orca/.local/share/orca-server-guard/bin:')
print(f'Schede: {len(before_ids)} prima, {len(after_ids)} dopo; mancanti: {len(missing)}; non connesse: {len(disconnected)}')
print(f'Claude: {len(old_claude)} prima, {len(new_claude)} dopo; PID persi: {len(lost_claude)}')
print(f'Demone originale: {daemon_pid}; vivo: {daemon_alive}; cgroup: {daemon_scope}')
print(f'Servizio nuovo: {server_pid}; PATH del plugin attivo: {plugin_path_active}')
for label, values in [('Schede mancanti', missing), ('Schede non connesse', disconnected), ('Claude persi', lost_claude)]:
    if values: print(label + ': ' + ', '.join(values))
if missing or disconnected or lost_claude or not daemon_alive or 'orca-serve.service' in daemon_scope or not plugin_path_active:
    print('ESITO: FALLITO')
    sys.exit(1)
print('ESITO: OK')
PY
  echo "Verifica conclusa: $(date -Is)"
}

result() {
  [[ -f $KIT/last-run ]] || { echo 'Nessun riavvio registrato'; return 1; }
  local run
  run=$(<"$KIT/last-run")
  [[ $run == "$KIT/restarts/"* ]] || { echo 'Percorso del risultato non valido' >&2; return 1; }
  [[ -f $run/result.log ]] || { echo "Riavvio ancora in corso: $run"; return 0; }
  cat "$run/result.log"
}

case ${1:-} in
  check) check ;;
  restart) restart ;;
  worker) shift; worker "$@" ;;
  result) result ;;
  *) echo "Uso: $SELF check|restart|result" >&2; exit 2 ;;
esac
