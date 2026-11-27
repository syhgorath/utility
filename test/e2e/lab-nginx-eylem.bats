#!/usr/bin/env bats
# LAB e2e: sabit hedefli nginx eylemleri (nginx_onizle, nginx_kur, nginx_yukselt) ve kurulum_durum'un nginx_* anahtarları (SUNUCUDAKİ gerçek durumdan).
# SIRALI testler. Gerçek VM yerine GEÇMEZ. Ağda TLS'i araya giren yazılım varsa: LAB_CA_FILE=<kök sertifika.pem>
# DİKKAT: macOS bash 3.2 ile bats, testin ortasındaki başarısız [[ ]] ifadesini YOK SAYAR; bu yüzden her [[ ]] "|| false" ile biter.
load ortak

# anahtar <ad>: son sonuç satırındaki değer (anahtar yoksa "-")
anahtar() { local v; v=$(result | tr ' ' '\n' | sed -n "s/^$1=//p"); echo "${v:--}"; }
# nginx_beklenen <kurulu> <mod> <port> <surum> <erisim>: kurulum_durum koşar ve beş anahtarı denetler
nginx_beklenen() {
  krun kurulum_durum
  [ "$status" -eq 0 ] || return 1
  [ "$(recap_changed)" = 0 ] || return 1
  local g
  g="$(anahtar nginx_kurulu) $(anahtar nginx_mod) $(anahtar nginx_port) $(anahtar nginx_surum) $(anahtar nginx_erisim)"
  [ "$g" = "$*" ] || { echo "beklenen: $*  gelen: $g" >&2; return 1; }
}
dinleyen() { lab sh -c "ss -ltnH | awk '{print \$4}' | grep -E ':$1\$' | sort | tr '\n' ' ' | sed 's/ \$//'"; }
yayin() { lab docker port kurulum-nginx 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
ozet() { lab sh -c "docker inspect -f '{{.Id}} {{.State.StartedAt}}' kurulum-nginx; sha256sum /srv/homelab/nginx/compose.yml /srv/homelab/.env /srv/homelab/.kurulum"; }

setup_file() {
  : > "$BATS_FILE_TMPDIR/hepsi.log"
  "$BATS_TEST_DIRNAME/lab/up.sh" >&3
}

@test "durum (temiz sunucu): nginx_kurulu=hayir, diğer nginx anahtarları yok; eski anahtarlar yerinde ve önde" {
  nginx_beklenen hayir yok yok yok yok
  [[ "$(result)" == "SSHPOCKET_RESULT utility.kurulum_durum ana_durum=yeni docker=yok kurulu=yok portlar=yok nginx_kurulu=hayir "* ]] || false
}

@test "nginx_kur hedefi sabittir: kurulum_yazilim=redis verilse de nginx kurulur, redis kurulmaz" {
  krun kur -e kurulum_yazilim=docker
  [ "$status" -eq 0 ]
  krun nginx_onizle -e kurulum_yazilim=redis -e kurulum_mod=docker
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.nginx_onizle yazilim=nginx mod=docker surum=1.30.6 port=8080 "* ]] || false
  run lab sh -c 'test ! -e /srv/homelab/nginx && echo temiz'
  [ "$output" = temiz ]
  krun nginx_kur -e kurulum_yazilim=redis -e kurulum_mod=docker
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.nginx_kur yazilim=nginx mod=docker "* ]] || false
  run lab sh -c 'docker ps -a --format "{{.Names}}" | tr "\n" " "; test ! -e /srv/homelab/redis && echo redis-yok'
  [[ "$output" == *kurulum-nginx*redis-yok* ]] || false
  [[ "$output" != *kurulum-redis* ]] || false
  nginx_beklenen evet docker 8080 1.30.6 sunucu
}

@test "kurulu docker nginx'te nginx_kur kurulu modu korur (kurulum_mod verilmez = native varsayılanı): port ve erişim uygulanır" {
  krun nginx_onizle -e kurulum_nginx_port=8081 -e kurulum_nginx_erisim=agdan
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEĞİŞECEK"*"8080 -> 8081"*"sunucu -> agdan"* ]] || false
  [ "$(yayin)" = "80/tcp -> 127.0.0.1:8080" ]
  krun nginx_kur -e kurulum_nginx_port=8081 -e kurulum_nginx_erisim=agdan
  [ "$status" -eq 0 ]
  [[ "$(result)" == *" mod=docker surum=1.30.6 port=8081 "* ]] || false
  [ "$(yayin)" = "80/tcp -> 0.0.0.0:8081" ]
  nginx_beklenen evet docker 8081 1.30.6 agdan
  krun nginx_kur -e kurulum_nginx_port=8081 -e kurulum_nginx_erisim=agdan
  [ "$(recap_changed)" = 0 ]
  [[ "$output" != *"DEĞİŞECEK"* ]] || false
}

@test "iç ağ: nginx_erisim=ic, nginx_port=ic" {
  krun nginx_kur -e kurulum_nginx_port=8081 -e kurulum_nginx_erisim=ic
  [ "$status" -eq 0 ]
  nginx_beklenen evet docker ic 1.30.6 ic
  krun nginx_kur -e kurulum_nginx_port=8081 -e kurulum_nginx_erisim=sunucu
  [ "$status" -eq 0 ]
  nginx_beklenen evet docker 8081 1.30.6 sunucu
}

@test "durum kayda değil sunucuya bakar: işaret yalan söylese de gerçek port ve erişim; durmuş konteyner = durmus" {
  lab sh -c "sed -i 's/\"port\": 8081/\"port\": 9999/; s/\"bind\": \"127.0.0.1\"/\"bind\": \"0.0.0.0\"/; s/\"surum\": \"1.30.6\"/\"surum\": \"9.9.9\"/' /srv/homelab/.kurulum"
  nginx_beklenen evet docker 8081 1.30.6 sunucu
  lab docker stop kurulum-nginx
  nginx_beklenen durmus docker unknown 1.30.6 unknown
  lab docker rm kurulum-nginx
  nginx_beklenen durmus docker unknown unknown unknown
  lab sh -c "sed -i 's/\"surum\": \"9.9.9\"/\"surum\": \"1.30.6\"/' /srv/homelab/.kurulum"   # yalan sürüm kaydı geri alınır (kur sürüm farkında reddeder)
  krun nginx_kur -e kurulum_nginx_port=8081
  [ "$status" -eq 0 ]
  nginx_beklenen evet docker 8081 1.30.6 sunucu
}

@test "docker hizmeti kapalıyken nginx durumu unknown (kurulu/durmuş iddiasında bulunulmaz)" {
  lab systemctl stop docker.socket docker
  nginx_beklenen unknown docker unknown unknown unknown
  lab systemctl start docker
  for _ in $(seq 1 30); do [ "$(yayin)" != "" ] && break; sleep 1; done
  nginx_beklenen evet docker 8081 1.30.6 sunucu
}

@test "sürüm: nginx_kur değiştirmez; nginx_onizle yukseltme=evet; nginx_yukselt yükseltir, port ve erişim korunur" {
  once=$(ozet)
  krun nginx_onizle -e kurulum_nginx_port=8081 -e kurulum_nginx_surum=1.31.8
  [[ "$(result)" == *" surum=1.31.8 port=8081 "*"yukseltme=evet"* ]] || false
  krun nginx_kur -e kurulum_nginx_port=8081 -e kurulum_nginx_surum=1.31.8
  [ "$status" -ne 0 ]
  [[ "$output" == *"nginx_yukselt"* ]] || false
  [ "$(ozet)" = "$once" ]
  krun nginx_yukselt -e kurulum_yazilim=redis -e kurulum_nginx_port=8081 -e kurulum_nginx_surum=1.31.8
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.nginx_yukselt yazilim=nginx mod=docker surum=1.31.8 port=8081 "* ]] || false
  nginx_beklenen evet docker 8081 1.31.8 sunucu
}

@test "kaldir sonrası: hayir/yok" {
  krun kaldir -e kurulum_yazilim=nginx -e kurulum_mod=docker
  [ "$status" -eq 0 ]
  nginx_beklenen hayir yok yok yok yok
}

@test "native: nginx_kur kurar; durum surum=dagitim ve gerçek dinleyeni bildirir" {
  krun nginx_kur -e kurulum_nginx_port=8081
  [ "$status" -eq 0 ]
  [[ "$(result)" == *" mod=native surum=dagitim port=8081 "* ]] || false
  nginx_beklenen evet native 8081 dagitim sunucu
}

@test "native kurulu iken kurulum_mod=docker verilse de kurulu mod korunur; ağdan açılır; ic reddedilir" {
  krun nginx_kur -e kurulum_mod=docker -e kurulum_nginx_port=8081 -e kurulum_nginx_erisim=agdan
  [ "$status" -eq 0 ]
  [[ "$(result)" == *" mod=native "* ]] || false
  nginx_beklenen evet native 8081 dagitim agdan
  krun nginx_kur -e kurulum_nginx_port=8081 -e kurulum_nginx_erisim=ic
  [ "$status" -ne 0 ]
  [[ "$output" == *"yalnız docker modunda"* ]] || false
  [ "$(dinleyen 8081)" = "0.0.0.0:8081" ]
}

@test "native durum dosyaya değil dinleyene bakar; durmuş servis = durmus; yukselt native'de reddedilir" {
  lab sed -i 's/listen 0.0.0.0:8081/listen 127.0.0.1:8081/' /etc/nginx/sites-available/kurulum
  nginx_beklenen evet native 8081 dagitim agdan
  lab systemctl stop nginx
  nginx_beklenen durmus native unknown dagitim unknown
  krun nginx_yukselt -e kurulum_nginx_port=8081
  [ "$status" -ne 0 ]
  [[ "$output" == *"native sürüm yükseltme"* ]] || false
  krun nginx_kur -e kurulum_nginx_port=8081
  [ "$status" -eq 0 ]
  nginx_beklenen evet native 8081 dagitim sunucu
}

@test "sonuç satırı sözleşmesi: 20 anahtar, her değer en çok 64 karakter ve yalnız izinli karakterler" {
  krun kurulum_durum
  [ "$(result | tr ' ' '\n' | grep -c '=')" = 20 ]
  run bash -c "printf '%s\n' '$(result)' | tr ' ' '\n' | sed -n 's/^[a-z_]*=//p' | grep -vE '^[A-Za-z0-9_.:+-]{1,64}\$' | wc -l | tr -d ' '"
  [ "$output" = 0 ]
}

@test "TEMİZ ÇIKTI: hiçbir koşuda beklenmeyen [WARNING] / [DEPRECATION WARNING] yok" {
  run beklenmeyen_uyarilar "$BATS_FILE_TMPDIR/hepsi.log"
  echo "$output" >&3
  [ "$status" -eq 1 ]
}
