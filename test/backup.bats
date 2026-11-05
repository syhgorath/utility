#!/usr/bin/env bats
# roles/common/files/utility_backup.py birim testleri (yerel; sunucu gerekmez). "root" = geçici dizin.
PY="${PYTHON:-python3}"
SCRIPT="$BATS_TEST_DIRNAME/../roles/common/files/utility_backup.py"

setup() {
  R="$BATS_TEST_TMPDIR/root"
  mkdir -p "$R/etc/default" "$R/etc/chrony/sources.d" "$R/usr/share/zoneinfo/Europe"
  ln -s ../usr/share/zoneinfo/Europe/Istanbul "$R/etc/localtime"
  printf 'LANG=C\n' > "$R/etc/default/locale"; chmod 644 "$R/etc/default/locale"
  printf 'a\n' > "$R/etc/chrony/sources.d/utility.sources"
}
req() { "$PY" -I "$SCRIPT" "$1"; }
jget() { "$PY" -I -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"; }

@test "backup: dizin 0700, dosyalar 0600, manifest var, yok olan 'absent'" {
  out=$(req '{"mode":"backup","root":"'"$R"'","dir":"/var/backups/utility","paths":["/etc/localtime","/etc/default/locale","/etc/chrony/sources.d/utility.sources","/etc/timezone"],"stamp":"20261105T101500Z"}')
  [ "$(jget "$out" saved)" = 4 ]
  d="$R/var/backups/utility/20261105T101500Z"
  [ "$(stat -f %Lp "$R/var/backups/utility" 2>/dev/null || stat -c %a "$R/var/backups/utility")" = 700 ]
  [ "$(stat -f %Lp "$d" 2>/dev/null || stat -c %a "$d")" = 700 ]
  [ "$(stat -f %Lp "$d/manifest.json" 2>/dev/null || stat -c %a "$d/manifest.json")" = 600 ]
  for f in "$d"/files/*; do [ "$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")" = 600 ]; done
  grep -q '"state": "absent"' "$d/manifest.json"
  grep -q '"state": "symlink"' "$d/manifest.json"
}

@test "backup: aynı saniyede ikinci yedek ezilmez" {
  a='{"mode":"backup","root":"'"$R"'","dir":"/var/backups/utility","paths":["/etc/localtime"],"stamp":"20261105T101500Z"}'
  req "$a" >/dev/null; out=$(req "$a")
  [[ "$(jget "$out" dir)" == *"20261105T101500Z-1" ]]
}

@test "backup: katalog dışı yol ve '..' reddedilir" {
  run req '{"mode":"backup","root":"'"$R"'","dir":"/var/backups/utility","paths":["/etc/shadow"]}'
  [ "$status" -eq 1 ]; [[ "$output" == *"katalog dışı"* ]]
  run req '{"mode":"backup","root":"'"$R"'","dir":"/var/backups/utility","paths":["/etc/chrony/sources.d/../../shadow"]}'
  [ "$status" -eq 1 ]
}

@test "restore: değişen dosyayı, bağı ve yok-olanı geri getirir; ikinci kez değişiklik yok" {
  req '{"mode":"backup","root":"'"$R"'","dir":"/var/backups/utility","paths":["/etc/localtime","/etc/default/locale","/etc/chrony/sources.d/utility.sources","/etc/timezone"],"stamp":"20261105T101500Z"}' >/dev/null
  ln -sfn ../usr/share/zoneinfo/Europe/London "$R/etc/localtime"
  printf 'LANG=en_US.UTF-8\n' > "$R/etc/default/locale"
  rm "$R/etc/chrony/sources.d/utility.sources"
  echo Europe/London > "$R/etc/timezone"
  out=$(req '{"mode":"restore","root":"'"$R"'","dir":"/var/backups/utility","from":""}')
  [ "$(jget "$out" changed)" = 4 ]
  [ "$(readlink "$R/etc/localtime")" = "../usr/share/zoneinfo/Europe/Istanbul" ]
  [ "$(cat "$R/etc/default/locale")" = "LANG=C" ]
  [ "$(cat "$R/etc/chrony/sources.d/utility.sources")" = a ]
  [ ! -e "$R/etc/timezone" ]
  out=$(req '{"mode":"restore","root":"'"$R"'","dir":"/var/backups/utility","from":""}')
  [ "$(jget "$out" changed)" = 0 ]
}

@test "restore: dry_run hiçbir şey yazmaz" {
  req '{"mode":"backup","root":"'"$R"'","dir":"/var/backups/utility","paths":["/etc/default/locale"],"stamp":"20261105T101500Z"}' >/dev/null
  printf 'LANG=x\n' > "$R/etc/default/locale"
  out=$(req '{"mode":"restore","root":"'"$R"'","dir":"/var/backups/utility","from":"","dry_run":true}')
  [ "$(jget "$out" changed)" = 1 ]
  [ "$(cat "$R/etc/default/locale")" = "LANG=x" ]
}

@test "restore: kurcalanmış manifest katalog dışı yola yazamaz, bozuk yedek reddedilir" {
  req '{"mode":"backup","root":"'"$R"'","dir":"/var/backups/utility","paths":["/etc/default/locale"],"stamp":"20261105T101500Z"}' >/dev/null
  m="$R/var/backups/utility/20261105T101500Z/manifest.json"
  sed -i.bak 's#"/etc/default/locale"#"/etc/passwd"#' "$m"
  out=$(req '{"mode":"restore","root":"'"$R"'","dir":"/var/backups/utility","from":""}')
  [ "$(jget "$out" skipped)" = 1 ]
  [ ! -e "$R/etc/passwd" ]
  mv "$m.bak" "$m"; echo tamper >> "$R/var/backups/utility/20261105T101500Z/files/0"
  run req '{"mode":"restore","root":"'"$R"'","dir":"/var/backups/utility","from":""}'
  [ "$status" -eq 1 ]; [[ "$output" == *"yedek bozuk"* ]]
}

@test "restore: from biçimi doğrulanır, yedek yoksa hata" {
  run req '{"mode":"restore","root":"'"$R"'","dir":"/var/backups/utility","from":"../x"}'
  [ "$status" -eq 1 ]
  run req '{"mode":"restore","root":"'"$R"'","dir":"/var/backups/utility","from":""}'
  [ "$status" -eq 1 ]
}
