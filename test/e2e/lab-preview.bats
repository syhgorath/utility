#!/usr/bin/env bats
# LAB e2e: HER yazılım x mod için TEMİZ sunucuda `preview` (--check) başarılı olmalı ve sunucuya HİÇBİR ŞEY yazmamalı.
# Neden ayrı: --check'te apt paket kurmaz; paketin yaratacağı dosyalara (redis.conf, sites-available, ...) dokunan görevler kurulu değilken düşer
# (gerçek VM bulgusu V01-REDIS-NATIVE-PREVIEW). Docker modları için Docker taban kuruludur. SIRALI testler.
load ortak

setup_file() {
  : > "$BATS_FILE_TMPDIR/hepsi.log"
  "$BATS_TEST_DIRNAME/lab/up.sh" >&3
}

# sunucu durum özeti: yapılandırma/veri dosyaları + paket sayısı + konteyner sayısı
snap() { lab sh -c 'find /srv/homelab /etc/kurulum /etc/nginx /etc/mysql /etc/redis /etc/apt /etc/systemd -type f 2>/dev/null | sort | xargs -r sha256sum | sha256sum; dpkg -l | grep -c "^ii"; (docker ps -aq 2>/dev/null | wc -l)'; }

onizle() {  # yazilim mod [ek -e ...]
  local yz=$1 mod=$2; shift 2
  local once; once=$(snap)
  krun kurulum_onizle -e "kurulum_yazilim=$yz" -e "kurulum_mod=$mod" "$@"
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.kurulum_onizle yazilim=$yz mod=$mod "* ]]
  [ "$(snap)" = "$once" ]
}

@test "temiz sunucu: preview nginx native" { onizle nginx native; }
@test "temiz sunucu: preview mariadb native" { onizle mariadb native; }
@test "temiz sunucu: preview redis native" { onizle redis native; }
@test "temiz sunucu: preview docker taban" { onizle docker native; }

@test "Docker taban kurulur (docker modları için ön koşul)" {
  krun kur -e kurulum_yazilim=docker
  [ "$status" -eq 0 ]
}

@test "Docker kuruluyken: preview nginx/mariadb/redis docker (uygulama dizini yok)" {
  onizle nginx docker
  onizle mariadb docker
  onizle redis docker
}

@test "artık .env (kaldırılmış uygulamadan) varken redis native preview (VM durumu)" {
  lab sh -c 'mkdir -p /srv/homelab/redis && echo "REDIS_PASSWORD=lab-sahte-deger-yalniz-test" > /srv/homelab/redis/.env && chmod 600 /srv/homelab/redis/.env'
  onizle redis native
}

@test "TEMİZ ÇIKTI: hiçbir koşuda beklenmeyen [WARNING] / [DEPRECATION WARNING] yok" {
  run beklenmeyen_uyarilar "$BATS_FILE_TMPDIR/hepsi.log"
  [ "$status" -eq 1 ]
}
