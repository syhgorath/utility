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

@test "Proxmox VE reddedilir (sahte pveversion), --check dahil; hiçbir şey değişmez" {
  lab sh -c 'touch /usr/bin/pveversion'
  run "$RUN" preview -e "@$(v1)" --check --diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"Proxmox VE tespit edildi"* ]] || false
  run "$RUN" apply -e "@$(v1)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Proxmox VE tespit edildi"* ]] || false
  lab sh -c 'rm /usr/bin/pveversion; mkdir /etc/pve'
  run "$RUN" apply -e "@$(v1)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Proxmox VE tespit edildi"* ]] || false
  lab sh -c 'rmdir /etc/pve'
  run "$RUN" preview -e "@$(v1)" --check
  [ "$status" -eq 0 ]
}

# --- timedated önbelleği ---
@test "timedated: apply ve geri_yukle sonrası timedatectl dosyayla uyumlu" {
  run lab timedatectl show -p Timezone      # önbelleği doldurur
  [ "$output" = "Timezone=Etc/UTC" ]
  run "$RUN" apply -e "@$(v2)"
  [ "$status" -eq 0 ]
  run lab timedatectl show -p Timezone
  [ "$output" = "Timezone=America/New_York" ]
  run "$RUN" geri_yukle
  [ "$status" -eq 0 ]
  run lab timedatectl show -p Timezone
  [ "$output" = "Timezone=Etc/UTC" ]
}

# --- saat sapması (SAHTE chronyc: LAB'da chronyd ve saat adımlama yok; yalnızca utility_clock.py + playbook akışı sınanır) ---
stub_on() {
  docker cp "$BATS_TEST_DIRNAME/lab/chronyc-stub.sh" utility-lab:/usr/local/bin/chronyc
  lab sh -c 'mkdir -p /run/utility-stub && cd /run/utility-stub && echo -1152060 > offset && echo 377 > reach && echo 0 > selected && rm -f steps'
}

@test "saat sapması: durum ntp_senkron=no ve sapmayı gösterir" {
  stub_on
  run "$RUN" durum
  [ "$status" -eq 0 ]
  [[ "$(result)" == *" ntp_senkron=no "* && "$(result)" == *" sapma_ms=1152060000.0 secili_kaynak=no saat_sapma_kontrolcuye_gore_sn="* ]]
}

@test "saat sapması: preview 'saat' planlar ve hiçbir şey adımlamaz" {
  run "$RUN" preview --check --diff
  [ "$status" -eq 0 ]
  [ "$(result)" = "SSHPOCKET_RESULT utility.preview degisen=1 plan=saat" ]
  [[ "$output" == *"apply chrony ile TEK SEFERLİK adımlayacak"* ]]
  run lab sh -c 'test ! -e /run/utility-stub/steps && echo temiz'
  [ "$output" = temiz ]
}

@test "saat sapması: utility_ntp_makestep=false sapmaya dokunmaz" {
  run "$RUN" preview --check -e utility_ntp_makestep=false
  [ "$(result)" = "SSHPOCKET_RESULT utility.preview degisen=0 plan=yok" ]
}

@test "saat sapması: apply tek seferlik makestep yapar, ikinci apply changed=0" {
  run "$RUN" apply
  [ "$status" -eq 0 ]
  [ "$(result)" = "SSHPOCKET_RESULT utility.apply degisen=1 plan=saat yedek=hayir" ]
  [[ "$output" == *"saat adımlandı"* ]]
  run lab sh -c 'wc -l < /run/utility-stub/steps'
  [ "$output" = 1 ]
  run "$RUN" apply
  [ "$(result)" = "SSHPOCKET_RESULT utility.apply degisen=0 plan=yok yedek=hayir" ]
  [ "$(recap_changed)" = 0 ]
  run lab sh -c 'wc -l < /run/utility-stub/steps'
  [ "$output" = 1 ]
  run "$RUN" durum
  [[ "$(result)" == *" ntp_senkron=yes "* && "$(result)" == *" secili_kaynak=yes saat_sapma_kontrolcuye_gore_sn="* ]]
}

@test "saat sapması: makestep düzeltmezse apply net hatayla düşer" {
  lab sh -c 'echo -1152060 > /run/utility-stub/offset; echo 0 > /run/utility-stub/selected; printf "#!/bin/sh\ncase \"\$*\" in \"-c tracking\") echo 00000000,,0,0,0;; \"-c sources\") echo ^,?,n,2,6,377,1,-5000.0,0,0;; esac\n" > /usr/local/bin/chronyc'
  run "$RUN" apply -e utility_ntp_step_timeout_s=4
  [ "$status" -ne 0 ]
  [[ "$output" == *"adimlanamadi"* ]]
  lab rm -f /usr/local/bin/chronyc
}

# --- kontrolcü saatiyle karşılaştırma (GERÇEK VM bulgusu: chrony bayat durumda sapmayı göstermedi). SAHTE date + SAHTE chronyc ---
ctrl_on() { # $1=skew sn, $2=chrony: stale (seçili, ofset~0) | none (kaynak yok)
  docker cp "$BATS_TEST_DIRNAME/lab/chronyc-stub.sh" utility-lab:/usr/local/bin/chronyc
  docker cp "$BATS_TEST_DIRNAME/lab/date-stub.sh" utility-lab:/usr/local/bin/date
  lab sh -c "mkdir -p /run/utility-stub && cd /run/utility-stub && echo $1 > skew && rm -f steps datesets"
  if [ "$2" = stale ]; then lab sh -c 'cd /run/utility-stub && echo 0.0002 > offset && echo 377 > reach && echo 1 > selected'
  else lab sh -c 'cd /run/utility-stub && echo 0 > offset && echo 0 > reach && echo 0 > selected'; fi
}
ctrl_off() { lab rm -f /usr/local/bin/chronyc /usr/local/bin/date; }

@test "kontrolcü farkı: chrony 'sapma yok' dese de durum ntp_senkron=no ve farkı gösterir" {
  ctrl_on -1123200 stale
  run "$RUN" durum
  [ "$status" -eq 0 ]
  [[ "$(result)" == *" sapma_ms=0.2 "* && "$(result)" == *" ntp_senkron=no "* ]]
  [[ "$(result)" =~ saat_sapma_kontrolcuye_gore_sn=-11232[0-9][0-9]$ ]] || [[ "$(result)" =~ saat_sapma_kontrolcuye_gore_sn=-11231[0-9][0-9]$ ]]
}

@test "kontrolcü farkı: preview 'saat' planlar, uyarır, hiçbir şey değiştirmez" {
  run "$RUN" preview --check
  [ "$status" -eq 0 ]
  [ "$(result)" = "SSHPOCKET_RESULT utility.preview degisen=1 plan=saat" ]
  [[ "$output" == *"kontrol makinesine göre"* && "$output" == *"utility_ntp_clock_from_controller=false"* ]]
  run lab sh -c 'test ! -e /run/utility-stub/datesets && echo temiz'
  [ "$output" = temiz ]
}

@test "kontrolcü farkı: makestep=false ve seçenek kapalıyken plan boş, yalnız uyarı" {
  run "$RUN" preview --check -e utility_ntp_makestep=false
  [ "$(result)" = "SSHPOCKET_RESULT utility.preview degisen=0 plan=yok" ]
  [[ "$output" == *"kontrol makinesine göre"* ]]
}

@test "kontrolcü farkı: chrony taze kaynakla doğruluyorsa kontrolcü saatine DOKUNULMAZ (seçenek açık olsa bile)" {
  run "$RUN" apply -e utility_ntp_clock_from_controller=true
  [ "$status" -eq 0 ]
  [[ "$output" == *"hâlâ"* ]]
  run lab sh -c 'test ! -e /run/utility-stub/datesets && echo temiz'
  [ "$output" = temiz ]
}

@test "kontrolcü farkı: kaynak yoksa seçenek açıkken date -s ile kontrolcü saatine ayarlar; ikinci apply boş" {
  ctrl_on -1123200 none
  run "$RUN" apply -e utility_ntp_clock_from_controller=true
  [ "$status" -eq 0 ]
  [ "$(result)" = "SSHPOCKET_RESULT utility.apply degisen=1 plan=saat yedek=hayir" ]
  [[ "$output" == *"KONTROL MAKİNESİNİN saatine ayarlandı"* ]]
  run lab sh -c 'wc -l < /run/utility-stub/datesets'
  [ "$output" = 1 ]
  run "$RUN" apply -e utility_ntp_clock_from_controller=true
  [ "$(result)" = "SSHPOCKET_RESULT utility.apply degisen=0 plan=yok yedek=hayir" ]
}

@test "kontrolcü farkı: seçenek kapalıyken kaynak yoksa saat DEĞİŞMEZ, açık uyarı verir" {
  ctrl_on -1123200 none
  run "$RUN" apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"hâlâ"* ]]
  run lab sh -c 'test ! -e /run/utility-stub/datesets && echo temiz'
  [ "$output" = temiz ]
}

@test "kontrolcü farkı: eşik altı fark (60 sn) planlanmaz" {
  ctrl_on -60 none
  run "$RUN" preview --check
  [ "$(result)" = "SSHPOCKET_RESULT utility.preview degisen=0 plan=yok" ]
  ctrl_off
}

teardown_file() { "$BATS_TEST_DIRNAME/lab/down.sh" --clean >&3 || true; }
