#!/usr/bin/env bats
# roles/ortak/files/duvar_oku.py birim testleri (yerel; sunucu gerekmez). ufw, iptables ve systemctl SAHTEDİR; "root" = geçici dizin.
# DİKKAT: macOS bash 3.2 ile bats, testin ortasındaki başarısız [[ ]] ifadesini YOK SAYAR; bu yüzden her [[ ]] "|| false" ile biter.
# shellcheck disable=SC2016  # sahte komutların içindeki $ ifadeleri bilerek yazıldığı gibi kalır
SCRIPT="$BATS_TEST_DIRNAME/../roles/ortak/files/duvar_oku.py"

setup() {
  PY=$(command -v "${PYTHON:-python3}")
  D="$BATS_TEST_TMPDIR"; B="$D/bin"; R="$D/root"; LOG="$D/cagri.log"
  mkdir -p "$B" "$R/etc/ufw" "$R/etc/docker"
  : > "$LOG"; : > "$R/etc/ufw/user.rules"; : > "$D/etkin"
  sahte ufw '/bin/cat '"$D"'/ufw.out; exit $(/bin/cat '"$D"'/ufw.rc)'
  sahte iptables '/bin/cat '"$D"'/ipt.out; exit $(/bin/cat '"$D"'/ipt.rc)'
  sahte systemctl 'if /usr/bin/grep -qx "$2" '"$D"'/etkin; then echo active; exit 0; fi; echo inactive; exit 3'
  ufw_acik deny
  echo 0 > "$D/ipt.rc"; printf -- '-N DOCKER-USER\n' > "$D/ipt.out"
}
sahte() { printf '#!/bin/sh\necho "%s $*" >> %s\n%s\n' "$1" "$LOG" "$2" > "$B/$1"; chmod +x "$B/$1"; }
# ufw_acik <gelen varsayılanı>
ufw_acik() {
  echo 0 > "$D/ufw.rc"
  printf 'Status: active\nLogging: on (low)\nDefault: %s (incoming), allow (outgoing), disabled (routed)\nNew profiles: skip\n' "$1" > "$D/ufw.out"
}
# kural <tuple alanları>  (ufw'nin /etc/ufw/user.rules biçimi)
kural() { printf '\n### tuple ### %s\n-A ufw-user-input -j ACCEPT\n' "$*" >> "$R/etc/ufw/user.rules"; }
sifirla() { : > "$R/etc/ufw/user.rules"; }
# oku <mod> <erisim> <port>  -> JSON
oku() { PATH="$B" "$PY" -I - "{\"mod\":\"$1\",\"erisim\":\"$2\",\"port\":\"$3\",\"root\":\"$R\",\"ek_yol\":\"\"}" < "$SCRIPT"; }
# bekle <değer> [mod erisim port]  (varsayılan: native agdan 8080)
bekle() {
  local g
  g=$(oku "${2:-native}" "${3:-agdan}" "${4:-8080}" | "$PY" -I -c 'import json,sys; print(json.load(sys.stdin)["duvar"])')
  [ "$g" = "$1" ] || { echo "beklenen=$1 gelen=$g ($*) kurallar: $(grep '^###' "$R/etc/ufw/user.rules" | tr '\n' ';')" >&2; return 1; }
}

@test "gerekmez: port ağa açık değilse hiçbir komut koşmaz" {
  for e in yok ic sunucu; do
    bekle gerekmez native "$e" 8080
    bekle gerekmez docker "$e" ic
  done
  [ ! -s "$LOG" ]
}

@test "unknown: erişim, port ya da mod okunamadıysa tahmin edilmez" {
  bekle unknown native unknown 8080
  bekle unknown native agdan unknown
  bekle unknown native agdan ic
  bekle unknown native agdan 0
  bekle unknown yok agdan 8080
}

@test "SALT OKUNUR: yalnız üç okuma komutu koşar" {
  bekle engelliyor
  bekle atlanir docker
  printf 'Status: inactive\n' > "$D/ufw.out"
  bekle acik
  [ "$(sort -u "$LOG")" = "$(printf 'iptables -S DOCKER-USER\nsystemctl is-active firewalld\nsystemctl is-active nftables\nufw status verbose')" ]
}

@test "engelliyor: ufw açık, gelen reddediliyor, porta izin kuralı yok" {
  bekle engelliyor
  ufw_acik reject; bekle engelliyor
}

@test "engelliyor: portu ilgilendirmeyen kurallar izin sayılmaz" {
  kural allow tcp 22 0.0.0.0/0 any 0.0.0.0/0 in
  kural allow udp 8080 0.0.0.0/0 any 0.0.0.0/0 in
  kural allow tcp 8000:8079 0.0.0.0/0 any 0.0.0.0/0 in
  kural allow tcp 80,808 0.0.0.0/0 any 10.0.0.0/8 in
  kural allow tcp 8080 0.0.0.0/0 any 0.0.0.0/0 out
  kural route:allow tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in
  kural allow any any 0.0.0.0/0 any 0.0.0.0/0 in_lo
  bekle engelliyor
}

@test "acik: porta herkesten izin (tek port, liste, aralık, her port, limit, log, yorum, uygulama profili)" {
  for k in "allow tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in" \
           "allow any 8080 0.0.0.0/0 any 0.0.0.0/0 in" \
           "allow tcp 80,8080 0.0.0.0/0 any 0.0.0.0/0 in" \
           "allow tcp 8000:8100 0.0.0.0/0 any 0.0.0.0/0 in" \
           "allow any any 0.0.0.0/0 any 0.0.0.0/0 in" \
           "limit tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in" \
           "allow_log tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in comment=6e67696e78" \
           "allow tcp 8080 0.0.0.0/0 any 0.0.0.0/0" \
           "allow tcp 80,8080 0.0.0.0/0 any 0.0.0.0/0 Nginx%20Full - in"; do
    sifirla; kural "$k"; bekle acik || return 1
  done
}

@test "acik: ufw kurulu değil ya da kapalı; varsayılan izin" {
  printf 'Status: inactive\n' > "$D/ufw.out"; bekle acik
  rm "$B/ufw"; bekle acik
  sahte ufw '/bin/cat '"$D"'/ufw.out; exit 0'
  ufw_acik allow; bekle acik
}

@test "kisitli: yalnız bazı kaynaklara, adreslere, arayüze ya da kaynak portuna izin" {
  for k in "allow tcp 8080 0.0.0.0/0 any 192.168.1.0/24 in" \
           "allow any any 0.0.0.0/0 any 10.0.0.0/8 in" \
           "allow tcp 8080 192.168.1.10 any 0.0.0.0/0 in" \
           "allow tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in_eth0" \
           "allow tcp 8080 0.0.0.0/0 5000 0.0.0.0/0 in"; do
    sifirla; kural "$k"; bekle kisitli || return 1
  done
}

@test "kural sırası: ilk eşleşen kazanır" {
  kural deny tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in
  kural allow tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in
  bekle engelliyor
  sifirla; kural allow tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in; kural deny tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in
  bekle acik
  sifirla; kural deny any any 0.0.0.0/0 any 203.0.113.7 in; kural allow tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in
  bekle kisitli
  sifirla; kural allow tcp 8080 0.0.0.0/0 any 192.168.1.0/24 in; kural reject tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in
  bekle kisitli
  sifirla; kural deny tcp 8080 0.0.0.0/0 any 203.0.113.7 in
  bekle engelliyor
}

@test "varsayılan izin: yalnız ret kuralları daraltır" {
  ufw_acik allow
  kural deny tcp 8080 0.0.0.0/0 any 203.0.113.7 in; bekle kisitli
  sifirla; kural deny tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in; bekle engelliyor
}

@test "unknown: ufw okunamıyor, çıktı ya da kural biçimi anlaşılmıyor" {
  echo 1 > "$D/ufw.rc"; bekle unknown
  ufw_acik deny; printf 'baska bir cikti\n' > "$D/ufw.out"; bekle unknown
  printf 'Status: active\n' > "$D/ufw.out"; bekle unknown
  ufw_acik deny; kural allow tcp 8080; bekle unknown
  sifirla; kural gizemli tcp 8080 0.0.0.0/0 any 0.0.0.0/0 in; bekle unknown
  sifirla; kural allow tcp http 0.0.0.0/0 any 0.0.0.0/0 in; bekle unknown
  rm "$R/etc/ufw/user.rules"; bekle unknown
}

@test "unknown: ufw yok/kapalıyken başka güvenlik duvarı servisi çalışıyor" {
  printf 'Status: inactive\n' > "$D/ufw.out"
  for s in firewalld nftables; do
    echo "$s" > "$D/etkin"; bekle unknown || return 1
  done
  rm "$B/ufw"; bekle unknown
  : > "$D/etkin"; rm "$B/systemctl"; bekle unknown
}

@test "atlanir: docker yayını ufw'den bağımsız (ufw açık ve kuralsız olsa da)" {
  bekle atlanir docker
  printf -- '-N DOCKER-USER\n-A DOCKER-USER -j RETURN\n' > "$D/ipt.out"; bekle atlanir docker
  printf '{"log-driver":"journald","iptables":true}\n' > "$R/etc/docker/daemon.json"; bekle atlanir docker
}

@test "unknown: docker'da atlama kesin değilse (DOCKER-USER kuralı, iptables kapalı, okunamayan ayar)" {
  printf -- '-N DOCKER-USER\n-A DOCKER-USER -i eth0 -j DROP\n' > "$D/ipt.out"; bekle unknown docker
  printf -- '-N DOCKER-USER\n' > "$D/ipt.out"
  printf '{"iptables": false}\n' > "$R/etc/docker/daemon.json"; bekle unknown docker
  printf 'bozuk{\n' > "$R/etc/docker/daemon.json"; bekle unknown docker
  rm "$R/etc/docker/daemon.json"
  echo 1 > "$D/ipt.rc"; bekle unknown docker
  rm "$B/iptables"; bekle unknown docker
}
