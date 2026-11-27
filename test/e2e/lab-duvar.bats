#!/usr/bin/env bats
# LAB e2e: <uyg>_duvar okuması GERÇEK ufw ile (ufw yok/kapalı/açık; izin kuralı yok/kısmi/herkese) ve söylenen değerin ağdan erişimle uyumu
# (ikinci bir konteyner LAB sunucusuna bağlanır). SIRALI testler. Gerçek VM yerine GEÇMEZ. ufw kurallarını TEST ekler; paket yazmaz.
# Ağda TLS'i araya giren yazılım varsa: LAB_CA_FILE=<kök sertifika.pem>
# DİKKAT: macOS bash 3.2 ile bats, testin ortasındaki başarısız [[ ]] ifadesini YOK SAYAR; bu yüzden her [[ ]] "|| false" ile biter.
# shellcheck disable=SC2016  # tek tırnak içindeki $ ifadeleri bilerek sunucuda genişler
load ortak

anahtar() { local v; v=$(result | tr ' ' '\n' | sed -n "s/^$1=//p"); echo "${v:--}"; }
# duvar_bekle <uygulama> <erisim> <duvar> <duvar_engel>
duvar_bekle() {
  krun "$1_durum"
  [ "$status" -eq 0 ] || return 1
  [ "$(recap_changed)" = 0 ] || return 1
  local g
  g="$(anahtar "$1_erisim") $(anahtar "$1_duvar") $(anahtar "$1_duvar_engel")"
  [ "$g" = "$2 $3 $4" ] || { echo "$1 beklenen: $2 $3 $4  gelen: $g" >&2; lab ufw status verbose >&2; return 1; }
}
# LAB sunucusunun dışından (aynı Docker ağındaki ayrı konteyner) porta TCP bağlantısı kurulabiliyor mu
ulasilir() {
  local ip img
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' kurulum-lab)
  img=$(docker inspect -f '{{.Config.Image}}' kurulum-lab)
  docker run --rm --entrypoint timeout "$img" 5 bash -c "</dev/tcp/$ip/$1" 2>/dev/null
}
# ufw ve iptables durumunun özeti (sayaçlar hariç): okuma bunu değiştirmemeli
duvar_ozeti() { lab sh -c 'cat /etc/ufw/ufw.conf /etc/ufw/user.rules /etc/ufw/user6.rules /etc/default/ufw | sha256sum; iptables -S | sha256sum; iptables -t nat -S | sha256sum'; }
ufw_() { lab ufw "$@" >/dev/null; }

setup_file() {
  : > "$BATS_FILE_TMPDIR/hepsi.log"
  "$BATS_TEST_DIRNAME/lab/up.sh" >&3
}

@test "hazırlık: native redis ağdan (6379), docker nginx ağdan (8081), ufw kurulu değil" {
  krun docker_kur
  [ "$status" -eq 0 ]
  krun nginx_kur -e kurulum_nginx_mod=docker -e kurulum_nginx_erisim=agdan -e kurulum_nginx_port=8081
  [ "$status" -eq 0 ]
  krun redis_kur -e kurulum_redis_mod=native -e kurulum_redis_erisim=agdan
  [ "$status" -eq 0 ]
  run lab sh -c '! command -v ufw >/dev/null && ss -ltnH | grep -c "0.0.0.0:6379"'
  [ "$output" = 1 ]
}

@test "ufw yok: native acik, docker atlanir; ikisine de ağdan erişilir" {
  duvar_bekle redis agdan acik hayir
  duvar_bekle nginx agdan atlanir hayir
  duvar_bekle mariadb yok gerekmez hayir
  ulasilir 6379
  ulasilir 8081
}

@test "ufw kurulu ama kapalı: acik" {
  run lab sh -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y -q ufw >/dev/null 2>&1 && ufw status'
  [ "$output" = "Status: inactive" ]
  duvar_bekle redis agdan acik hayir
}

@test "ufw açık, gelen reddediliyor, port kuralı yok: engelliyor + uyarı; gerçekten erişilemiyor. Docker portu atlanir ve erişiliyor" {
  ufw_ default deny incoming
  ufw_ allow 22/tcp
  ufw_ --force enable
  duvar_bekle redis agdan engelliyor evet
  [[ "$output" == *"ufw 6379/tcp için izin vermiyor"* ]] || false
  [[ "$output" == *"from <yönetim ağı> to any port 6379 proto tcp"* ]] || false
  run ulasilir 6379
  [ "$status" -ne 0 ]
  duvar_bekle nginx agdan atlanir hayir
  [[ "$output" != *"için izin vermiyor"* ]] || false
  ulasilir 8081
}

@test "yalnız bir ağa izin: kisitli (o ağın dışından erişilemiyor)" {
  ufw_ allow from 192.0.2.0/24 to any port 6379 proto tcp
  duvar_bekle redis agdan kisitli hayir
  run ulasilir 6379
  [ "$status" -ne 0 ]
  ufw_ delete allow from 192.0.2.0/24 to any port 6379 proto tcp
  duvar_bekle redis agdan engelliyor evet
}

@test "yalnız bir arayüze izin: kisitli" {
  ufw_ allow in on eth0 to any port 6379 proto tcp
  duvar_bekle redis agdan kisitli hayir
  ufw_ delete allow in on eth0 to any port 6379 proto tcp
}

@test "herkese izin kuralı: acik ve erişiliyor (tek port, aralık, uygulama profili)" {
  ufw_ allow 6379/tcp
  duvar_bekle redis agdan acik hayir
  ulasilir 6379
  ufw_ delete allow 6379/tcp
  ufw_ allow 6000:6400/tcp
  duvar_bekle redis agdan acik hayir
  ufw_ delete allow 6000:6400/tcp
  lab sh -c 'printf "[LabRedis]\ntitle=lab\ndescription=lab\nports=6379,6380/tcp\n" > /etc/ufw/applications.d/lab'
  ufw_ allow LabRedis
  duvar_bekle redis agdan acik hayir
  ulasilir 6379
  ufw_ delete allow LabRedis
  duvar_bekle redis agdan engelliyor evet
}

@test "kural sırası: ilk eşleşen kazanır (önde herkese ret -> engelliyor; önde tek adrese ret -> kisitli)" {
  ufw_ deny 6000:6400/tcp
  ufw_ allow 6379/tcp
  duvar_bekle redis agdan engelliyor evet
  run ulasilir 6379
  [ "$status" -ne 0 ]
  ufw_ delete deny 6000:6400/tcp
  ufw_ insert 1 deny from 192.0.2.7
  duvar_bekle redis agdan kisitli hayir
  ulasilir 6379
  ufw_ delete deny from 192.0.2.7
  ufw_ delete allow 6379/tcp
  duvar_bekle redis agdan engelliyor evet
}

@test "varsayılan izin: acik" {
  ufw_ default allow incoming
  duvar_bekle redis agdan acik hayir
  ulasilir 6379
  ufw_ default deny incoming
}

@test "DOCKER-USER zincirine kural eklenmişse docker için unknown" {
  lab iptables -I DOCKER-USER -s 192.0.2.0/24 -j DROP
  duvar_bekle nginx agdan unknown unknown
  lab iptables -D DOCKER-USER -s 192.0.2.0/24 -j DROP
  duvar_bekle nginx agdan atlanir hayir
}

@test "okuma güvenlik duvarını DEĞİŞTİRMEZ (--check dahil)" {
  once=$(duvar_ozeti)
  krun redis_durum
  krun nginx_durum
  krun mariadb_durum
  krun redis_durum --check
  [ "$status" -eq 0 ]
  [ "$(anahtar redis_duvar)" = engelliyor ]
  [ "$(duvar_ozeti)" = "$once" ]
  # önceki okumalar da yazmamış olmalı (yinelenen kural özeti değiştirmez): geriye yalnız testin eklediği SSH izni kalır
  [ "$(lab ufw show added | grep '^ufw ')" = "ufw allow 22/tcp" ]
  [ "$(lab iptables -S DOCKER-USER)" = "-N DOCKER-USER" ]
}

@test "servis durmuşsa unknown; erişim sunucu ise gerekmez" {
  lab systemctl stop redis-server
  duvar_bekle redis unknown unknown unknown
  lab systemctl start redis-server
  krun redis_kur -e kurulum_redis_mod=native -e kurulum_redis_erisim=sunucu
  [ "$status" -eq 0 ]
  duvar_bekle redis sunucu gerekmez hayir
}

@test "TEMİZ ÇIKTI: hiçbir koşuda beklenmeyen [WARNING] / [DEPRECATION WARNING] yok" {
  run beklenmeyen_uyarilar "$BATS_FILE_TMPDIR/hepsi.log"
  echo "$output" >&3
  [ "$status" -eq 1 ]
}
