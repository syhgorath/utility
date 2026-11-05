#!/usr/bin/env bats
# LAB e2e: durum -> preview -> apply -> ikinci apply/preview changed=0 -> değişiklik -> geri_yukle. Sıralı testler (her biri öncekinin durumunu kullanır).
# Gereken: docker (Colima), ansible-core venv (.venv). Konteyner BAŞTAN kurulur (test/e2e/lab/up.sh). Gerçek VM yerine GEÇMEZ.
RUN="$BATS_TEST_DIRNAME/lab/run.sh"

setup_file() {
  "$BATS_TEST_DIRNAME/lab/up.sh" >&3
  export V1="$BATS_FILE_TMPDIR/v1.json" V2="$BATS_FILE_TMPDIR/v2.json"
  printf '{"utility_timezone":"Europe/Istanbul","utility_locale":"en_US.UTF-8","utility_ntp_servers":["pool 2.pool.ntp.org","time.cloudflare.com"]}' > "$V1"
  printf '{"utility_timezone":"America/New_York","utility_locale":"C.UTF-8","utility_ntp_servers":["time.cloudflare.com"]}' > "$V2"
  echo "$V1" > "$BATS_FILE_TMPDIR/v1path"; echo "$V2" > "$BATS_FILE_TMPDIR/v2path"
}

lab() { docker exec utility-lab "$@"; }
tzfile() { lab sh -c "readlink -f /etc/localtime"; }
result() { grep -o 'SSHPOCKET_RESULT utility\.[a-z_]* .*' <<<"$output" | tail -n1 | sed 's/"$//'; }
recap_changed() { grep -E '^lab +:' <<<"$output" | sed -E 's/.*changed=([0-9]+).*/\1/'; }
v1() { cat "$BATS_FILE_TMPDIR/v1path"; }
v2() { cat "$BATS_FILE_TMPDIR/v2path"; }

@test "durum: salt okunur, yalın imajda çalışır ve değişiklik yapmaz" {
  run "$RUN" durum
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.durum timezone=Etc_UTC locale=unset ntp_servis="* ]]
  [[ "$(result)" == *" ntp_senkron="*" offset_ms="*" kaynak_sayisi="* ]]
}

@test "preview: değişiklik planlar ama HİÇBİR ŞEY yazmaz" {
  run "$RUN" preview -e "@$(v1)" --check --diff
  [ "$status" -eq 0 ]
  [ "$(result)" = "SSHPOCKET_RESULT utility.preview degisen=4 plan=timezone+locale+paket+ntp" ]
  [ "$(tzfile)" = "/usr/share/zoneinfo/Etc/UTC" ]
  run lab sh -c 'test ! -e /var/backups/utility && ! dpkg -s chrony >/dev/null 2>&1 && ! dpkg -s locales >/dev/null 2>&1 && echo temiz'
  [ "$output" = temiz ]
}

@test "apply: saat dilimi, locale ve chrony drop-in uygulanır; yedek 0700/0600" {
  run "$RUN" apply -e "@$(v1)"
  [ "$status" -eq 0 ]
  [ "$(result)" = "SSHPOCKET_RESULT utility.apply degisen=4 plan=timezone+locale+paket+ntp yedek=evet" ]
  [ "$(tzfile)" = "/usr/share/zoneinfo/Europe/Istanbul" ]
  run lab sh -c 'cat /etc/timezone; grep -h "^LANG=" /etc/default/locale; locale -a | grep -c en_US.utf8; cat /etc/chrony/sources.d/utility.sources'
  [[ "$output" == *"Europe/Istanbul"* && "$output" == *"LANG=en_US.UTF-8"* && "$output" == *"pool 2.pool.ntp.org iburst"* && "$output" == *"server time.cloudflare.com iburst"* ]]
  run lab sh -c 'stat -c "%a" /var/backups/utility /var/backups/utility/*/ /var/backups/utility/*/files | sort -u | tr "\n" " "; stat -c "%a" /var/backups/utility/*/manifest.json /var/backups/utility/*/files/* 2>/dev/null | sort -u | tr "\n" " "'
  [ "$output" = "700 600 " ]
  # chrony.conf'a dokunulmadı (paketle gelen dosya: sourcedir satırı duruyor, utility satırı eklemedi)
  run lab sh -c 'grep -c utility /etc/chrony/chrony.conf || true'
  [ "$output" = 0 ]
}

@test "ikinci apply changed=0 ve yedek almaz (idempotans)" {
  run "$RUN" apply -e "@$(v1)"
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
  [ "$(result)" = "SSHPOCKET_RESULT utility.apply degisen=0 plan=yok yedek=hayir" ]
  run lab sh -c 'ls /var/backups/utility | wc -l'
  [ "$output" = 1 ]
}

@test "ikinci preview degisen=0" {
  run "$RUN" preview -e "@$(v1)" --check --diff
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
  [ "$(result)" = "SSHPOCKET_RESULT utility.preview degisen=0 plan=yok" ]
}

@test "boş değişkenler hiçbir alana dokunmaz" {
  run "$RUN" apply
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
  [ "$(tzfile)" = "/usr/share/zoneinfo/Europe/Istanbul" ]
}

@test "durum uygulanan değerleri yansıtır" {
  run "$RUN" durum
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.durum timezone=Europe_Istanbul locale=en_US.UTF-8 ntp_servis="* ]]
}

@test "yeni değerler: ikinci yedek alınır ve yalnızca değişen yollar yedeklenir" {
  run "$RUN" apply -e "@$(v2)"
  [ "$status" -eq 0 ]
  [ "$(result)" = "SSHPOCKET_RESULT utility.apply degisen=3 plan=timezone+locale+ntp yedek=evet" ]
  [ "$(tzfile)" = "/usr/share/zoneinfo/America/New_York" ]
  run lab sh -c 'grep -h "^LANG=" /etc/default/locale; cat /etc/chrony/sources.d/utility.sources'
  [[ "$output" == *"LANG=C.UTF-8"* && "$output" != *"2.pool.ntp.org"* ]]
  run lab sh -c 'ls /var/backups/utility | wc -l'
  [ "$output" = 2 ]
}

@test "geri_yukle --check: yazmadan değişecek dosya sayısını söyler" {
  run "$RUN" geri_yukle --check
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.geri_yukle yedek="*" geri_yuklenen="*" degisen=3" ]]
  [ "$(tzfile)" = "/usr/share/zoneinfo/America/New_York" ]
}

@test "geri_yukle: en son yedekten dosyaları geri yazar" {
  run "$RUN" geri_yukle
  [ "$status" -eq 0 ]
  [ "$(tzfile)" = "/usr/share/zoneinfo/Europe/Istanbul" ]
  run lab sh -c 'cat /etc/timezone; grep -h "^LANG=" /etc/default/locale; cat /etc/chrony/sources.d/utility.sources'
  [[ "$output" == *"Europe/Istanbul"* && "$output" == *"LANG=en_US.UTF-8"* && "$output" == *"2.pool.ntp.org"* ]]
}

@test "geri_yukle ikinci kez degisen=0" {
  run "$RUN" geri_yukle
  [ "$status" -eq 0 ]
  [[ "$(result)" == *" degisen=0" ]]
  [ "$(recap_changed)" = 0 ]
}

@test "geri_yukle: ilk yedek (yalın sistem) dosya-olmayanı siler, paketleri geri almaz" {
  first=$(lab sh -c 'ls /var/backups/utility | sort | head -n1')
  run "$RUN" geri_yukle -e "utility_restore_from=$first"
  [ "$status" -eq 0 ]
  [ "$(tzfile)" = "/usr/share/zoneinfo/Etc/UTC" ]
  run lab sh -c 'test ! -e /etc/chrony/sources.d/utility.sources && dpkg -s chrony >/dev/null && echo ok'
  [ "$output" = ok ]
}

@test "geçersiz değişkenler uygulanmadan reddedilir" {
  run "$RUN" apply -e 'utility_timezone=../../etc/passwd'
  [ "$status" -ne 0 ]
  run "$RUN" apply -e 'utility_timezone=Mars/Olympus'
  [ "$status" -ne 0 ]
  run "$RUN" apply -e '{"utility_ntp_servers":["a b c"]}'
  [ "$status" -ne 0 ]
  run "$RUN" apply -e 'utility_locale=xx'
  [ "$status" -ne 0 ]
  run "$RUN" geri_yukle -e 'utility_restore_from=../x'
  [ "$status" -ne 0 ]
}

teardown_file() { "$BATS_TEST_DIRNAME/lab/down.sh" --clean >&3 || true; }
