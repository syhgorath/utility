#!/usr/bin/env bats
# roles/ntp/files/utility_clock.py birim testleri: sahte `chronyc` (PATH başına eklenir); sunucu/chrony gerekmez.
PY="${PYTHON:-python3}"
SCRIPT="$BATS_TEST_DIRNAME/../roles/ntp/files/utility_clock.py"

setup() {
  S="$BATS_TEST_TMPDIR/stub"; mkdir -p "$S/bin"
  # durum dosyaları: offset (saniye), reach, selected (1/0), makestep_needs_reach_after (sayaç: kaç `sources` çağrısından sonra reach>0)
  echo -1152060 > "$S/offset"; echo 377 > "$S/reach"; echo 0 > "$S/selected"
  cat > "$S/bin/chronyc" <<'STUB'
#!/usr/bin/env bash
S="$(dirname "$0")/.."
[ -f "$S/down" ] && exit 1
off=$(cat "$S/offset"); reach=$(cat "$S/reach"); sel=$(cat "$S/selected")
case "$*" in
  "-c tracking") if [ "$sel" = 1 ]; then echo "A9FE0101,x,3,0,$off,0,0,0,0,0,0,0,0"; else echo "00000000,,0,0,0,0,0,0,0,0,0,0,0"; fi ;;
  "-c sources") if [ "$sel" = 1 ]; then st='*'; else st='?'; fi; echo "^,$st,ntp.example,2,6,$reach,10,$off,0,0" ;;
  "makestep") if [ "$reach" != 0 ]; then echo 0.0002 > "$S/offset"; echo 1 > "$S/selected"; echo x >> "$S/steps"; fi ;;
esac
STUB
  chmod +x "$S/bin/chronyc"
  export PATH="$S/bin:$PATH"
}
req() { "$PY" -I "$SCRIPT" "$1"; }
jget() { "$PY" -I -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"; }

@test "status: seçili kaynak yokken erişilebilir kaynağın farkı sapma sayılır" {
  out=$(req '{"mode":"status"}')
  [ "$(jget "$out" up)" = True ]; [ "$(jget "$out" selected)" = False ]
  [ "$(jget "$out" source)" = kaynak ]; [ "$(jget "$out" drift_s)" = 1152060.0 ]
}

@test "status: seçili kaynak varsa tracking farkı" {
  echo 1 > "$S/selected"; echo 0.25 > "$S/offset"
  out=$(req '{"mode":"status"}')
  [ "$(jget "$out" source)" = tracking ]; [ "$(jget "$out" drift_s)" = 0.25 ]
}

@test "status: kaynaklar erişilemezse (reach 0) sapma null" {
  echo 0 > "$S/reach"
  out=$(req '{"mode":"status"}')
  [ "$(jget "$out" drift_s)" = None ]; [ "$(jget "$out" source)" = yok ]
}

@test "status: chronyc yoksa up=False" {
  touch "$S/down"
  out=$(req '{"mode":"status"}')
  [ "$(jget "$out" up)" = False ]
}

@test "step: büyük sapmayı chronyc makestep ile TEK kez adımlar" {
  out=$(req '{"mode":"step","threshold":1,"timeout":10,"interval":1}')
  [ "$(jget "$out" ok)" = True ]; [ "$(jget "$out" stepped)" = True ]
  [ "$(jget "$out" initial_drift_s)" = 1152060.0 ]
  [ "$(wc -l < "$S/steps" | tr -d ' ')" = 1 ]
}

@test "step: sapma küçükse hiçbir şey yapmaz (idempotans)" {
  echo 1 > "$S/selected"; echo 0.2 > "$S/offset"
  out=$(req '{"mode":"step","threshold":1,"timeout":10,"interval":1}')
  [ "$(jget "$out" ok)" = True ]; [ "$(jget "$out" stepped)" = False ]
  [ ! -e "$S/steps" ]
}

@test "step: kaynaklar hiç erişilebilir olmazsa kaynak_yok (adımlama denenmez)" {
  echo 0 > "$S/reach"
  out=$(req '{"mode":"step","threshold":1,"timeout":2,"interval":1}')
  [ "$(jget "$out" ok)" = False ]; [ "$(jget "$out" reason)" = kaynak_yok ]
  [ ! -e "$S/steps" ]
}

@test "step: ölçüldü ama makestep düzeltmezse adimlanamadi" {
  printf '#!/usr/bin/env bash\nS="$(dirname "$0")/.."\ncase "$*" in "-c tracking") echo "00000000,,0,0,0,0";; "-c sources") echo "^,?,n,2,6,377,1,-5000.0,0,0";; esac\n' > "$S/bin/chronyc"
  out=$(req '{"mode":"step","threshold":1,"timeout":3,"interval":1}')
  [ "$(jget "$out" ok)" = False ]; [ "$(jget "$out" reason)" = adimlanamadi ]
}

@test "step: chrony yoksa chrony_yok" {
  touch "$S/down"
  out=$(req '{"mode":"step","timeout":2,"interval":1}')
  [ "$(jget "$out" reason)" = chrony_yok ]
}

@test "geçersiz girdi JSON hata döner ve çıkış kodu 1" {
  run req '{"mode":"x"}'
  [ "$status" -eq 1 ]
}
