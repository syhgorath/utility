#!/usr/bin/env bash
# run.sh <eylem> [-e anahtar=değer ...] — LAB'a karşı component.json'daki eylemin KENDİ cmd'sini çalıştırır (sshpocket'in yaptığı gibi, onsuz).
# Menü/onay/ön koşul kapıları (sshpocket) burada YOKTUR; bu yalnızca playbook'ları dener. Ek argümanlar ansible-playbook'a geçer.
set -eu
L="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$L/../../.." && pwd)"; STATE="$L/.state"
[ -f "$STATE/inventory.yml" ] || { echo "LAB hazır değil: önce test/e2e/lab/up.sh"; exit 1; }
ACTION="${1:?kullanım: run.sh <durum|preview|apply|geri_yukle> [ansible argümanları]}"; shift
PY="${PYTHON:-$ROOT/.venv/bin/python}"; [ -x "$PY" ] || PY=python3
CMD=$("$PY" -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["actions"][sys.argv[2]]["cmd"])' "$ROOT/component.json" "$ACTION")
AP="${ANSIBLE_PLAYBOOK:-$ROOT/.venv/bin/ansible-playbook}"; [ -x "$AP" ] || AP=ansible-playbook
cd "$ROOT"
# shellcheck disable=SC2086  # cmd bilerek sözcüklere ayrılır (sshpocket de böyle yapar)
exec env ANSIBLE_HOST_KEY_CHECKING=True ANSIBLE_FORCE_COLOR=0 "$AP" -i "$STATE/inventory.yml" ${CMD#ansible-playbook } "$@"
