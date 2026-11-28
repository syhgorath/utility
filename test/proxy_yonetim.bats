#!/usr/bin/env bats
# roles/proxy/files/yonetim_karari.py birim testleri (yerel; sunucu gerekmez). "ip" SAHTEDİR; çıktısı gerçek "ip -4 -o addr show" biçimindedir.
# DİKKAT: macOS bash 3.2 ile bats, testin ortasındaki başarısız [[ ]] ifadesini YOK SAYAR; bu yüzden her [[ ]] "|| false" ile biter.
# shellcheck disable=SC2016  # sahte komutun içindeki $ ifadeleri bilerek yazıldığı gibi kalır
SCRIPT="$BATS_TEST_DIRNAME/../roles/proxy/files/yonetim_karari.py"

setup() {
  PY=$(command -v "${PYTHON:-python3}")
  D="$BATS_TEST_TMPDIR"; B="$D/bin"; LOG="$D/cagri.log"
  mkdir -p "$B"; : > "$LOG"
  printf '#!/bin/sh\necho "ip $*" >> %s\n/bin/cat %s/ip.out; exit $(/bin/cat %s/ip.rc)\n' "$LOG" "$D" "$D" > "$B/ip"; chmod +x "$B/ip"
  echo 0 > "$D/ip.rc"
}
# adres <inet alanından sonrası>...  -> geri döngü + verilen arayüzler
adres() {
  printf '1: lo    inet 127.0.0.1/8 scope host lo\\       valid_lft forever preferred_lft forever\n' > "$D/ip.out"
  local n=2 a
  for a in "$@"; do
    printf '%s: eth%s    inet %s brd 255.255.255.255 scope global eth%s\\       valid_lft forever preferred_lft forever\n' "$n" "$n" "$a" "$n" >> "$D/ip.out"
    n=$((n + 1))
  done
}
oku() { PATH="$B" "$PY" -I - '{"ek_yol":""}' < "$SCRIPT"; }
alan() { "$PY" -I -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])[sys.argv[2]], ensure_ascii=False, separators=(",",":")))' "$1" "$2"; }
# bekle <karar> <genel (JSON)>
bekle() {
  local j g
  j=$(oku); g="$(alan "$j" karar) $(alan "$j" genel)"
  [ "$g" = "\"$1\" $2" ] || { echo "beklenen: \"$1\" $2  gelen: $g  (adresler: $(cat "$D/ip.out"))" >&2; return 1; }
}

@test "agdan: yalnız geri döngü" {
  adres
  bekle agdan '[]'
}

@test "agdan: özel, link-local ve CGNAT adresleri genel sayılmaz (aralık sınırları dahil)" {
  for a in 10.0.0.5/8 172.16.0.1/12 172.31.255.254/12 192.168.1.20/24 169.254.10.1/16 100.64.0.1/10 100.127.255.254/10 198.18.0.1/15 192.0.2.10/24 203.0.113.9/24; do
    adres "$a"; bekle agdan '[]' || return 1
  done
  adres 10.1.2.3/24 192.168.5.5/24 100.100.100.100/32 172.17.0.1/16
  bekle agdan '[]'
}

@test "sunucu: genel IPv4 adresi (özel aralıkların hemen dışı dahil)" {
  for a in 8.8.8.8 1.1.1.1 9.255.255.255 11.0.0.1 100.63.255.255 100.128.0.1 172.15.255.255 172.32.0.1 192.167.1.1 192.169.1.1 169.253.1.1; do
    adres "$a/24"; bekle sunucu "[\"$a\"]" || return 1
  done
}

@test "sunucu: özel adreslerin arasında tek genel adres yeter; geri döngü arayüzündeki genel adres de sayılır" {
  adres 10.0.0.5/8 8.8.4.4/32 172.17.0.1/16
  bekle sunucu '["8.8.4.4"]'
  printf '1: lo    inet 127.0.0.1/8 scope host lo\n1: lo    inet 1.0.0.1/32 scope global lo\n' > "$D/ip.out"
  bekle sunucu '["1.0.0.1"]'
}

@test "noktadan noktaya arayüz: yerel uç değerlendirilir" {
  printf '1: lo    inet 127.0.0.1/8 scope host lo\n7: ppp0    inet 8.8.8.8 peer 10.0.0.1/32 scope global ppp0\n' > "$D/ip.out"
  bekle sunucu '["8.8.8.8"]'
  printf '1: lo    inet 127.0.0.1/8 scope host lo\n7: wg0    inet 10.0.0.2 peer 8.8.8.8/32 scope global wg0\n' > "$D/ip.out"
  bekle agdan '[]'
}

@test "okunamadı -> sunucu: komut hata verir, yok, boş ya da anlaşılmayan çıktı" {
  adres 192.168.1.2/24; echo 1 > "$D/ip.rc"; bekle sunucu null
  echo 0 > "$D/ip.rc"; : > "$D/ip.out"; bekle sunucu null
  printf 'beklenmeyen bir satir\n' > "$D/ip.out"; bekle sunucu null
  printf '1: lo    inet bozuk/8 scope host lo\n' > "$D/ip.out"; bekle sunucu null
  printf '1: lo    inet\n' > "$D/ip.out"; bekle sunucu null
  adres 192.168.1.2/24; printf '3: eth9    link/ether 00:00:00:00:00:00\n' >> "$D/ip.out"; bekle sunucu null
  rm "$B/ip"; adres 192.168.1.2/24; bekle sunucu null
}

@test "SALT OKUNUR ve yalnız IPv4: tek komut 'ip -4 -o addr show'" {
  adres 192.168.1.2/24
  oku >/dev/null
  [ "$(cat "$LOG")" = "ip -4 -o addr show" ]
}

@test "neden metni seçimi açıklar; NAT sınırını söyler" {
  adres 192.168.1.2/24; [[ "$(alan "$(oku)" neden)" == *"genel IPv4 adresi görünmüyor"*"NAT"* ]] || false
  adres 8.8.8.8/32; [[ "$(alan "$(oku)" neden)" == *"genel IPv4 adresi var: 8.8.8.8"* ]] || false
  echo 1 > "$D/ip.rc"; [[ "$(alan "$(oku)" neden)" == *"okunamadı"*"güvenli yön"* ]] || false
}
