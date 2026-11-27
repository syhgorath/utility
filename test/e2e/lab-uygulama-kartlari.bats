#!/usr/bin/env bats
# LAB e2e: Docker/MariaDB/Redis sabit eylemleri, kurulum_durum'un uygulama anahtarları (SUNUCUDAKİ gerçek durumdan), uygulama başına mod ve
# native MariaDB/Redis'te dinleme adresi/portunun gerçekten uygulanması. SIRALI testler. Gerçek VM yerine GEÇMEZ.
# Ağda TLS'i araya giren yazılım varsa: LAB_CA_FILE=<kök sertifika.pem>
# DİKKAT: macOS bash 3.2 ile bats, testin ortasındaki başarısız [[ ]] ifadesini YOK SAYAR; bu yüzden her [[ ]] "|| false" ile biter.
# shellcheck disable=SC2016  # tek tırnak içindeki $ ifadeleri bilerek sunucuda genişler
load ortak

anahtar() { local v; v=$(result | tr ' ' '\n' | sed -n "s/^$1=//p"); echo "${v:--}"; }
# beklenen <uygulama> <kurulu> <mod> <port> <surum> <erisim>: kurulum_durum koşar ve uygulamanın beş anahtarını denetler
beklenen() {
  local yz=$1; shift
  krun kurulum_durum
  [ "$status" -eq 0 ] || return 1
  [ "$(recap_changed)" = 0 ] || return 1
  local g
  g="$(anahtar "${yz}_kurulu") $(anahtar "${yz}_mod") $(anahtar "${yz}_port") $(anahtar "${yz}_surum") $(anahtar "${yz}_erisim")"
  [ "$g" = "$*" ] || { echo "$yz beklenen: $*  gelen: $g" >&2; return 1; }
}
# <süreç> adının dinlediği TCP adresleri
dinleyen() { lab sh -c "ss -ltnpH | grep '\"$1\"' | awk '{print \$4}' | sort -u | tr '\n' ' ' | sed 's/ \$//'"; }
yayin() { lab docker port "kurulum-$1" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
isaret_ozeti() { lab sh -c 'sha256sum /srv/homelab/.kurulum /srv/homelab/.env 2>/dev/null; docker ps -a --format "{{.Names}} {{.Image}}" | sort'; }

setup_file() {
  : > "$BATS_FILE_TMPDIR/hepsi.log"
  "$BATS_TEST_DIRNAME/lab/up.sh" >&3
}

@test "durum (temiz sunucu): docker/mariadb/redis anahtarları yok; 20 anahtar" {
  beklenen mariadb hayir yok yok yok yok
  [ "$(anahtar docker)" = yok ]
  [ "$(anahtar docker_servis)" = yok ]
  [ "$(anahtar redis_kurulu) $(anahtar redis_port)" = "hayir yok" ]
  [ "$(anahtar nginx_kurulu) $(anahtar nginx_port)" = "hayir yok" ]
  [ "$(result | tr ' ' '\n' | grep -c '=')" = 20 ]
}

@test "docker_onizle yazmaz; docker_kur hedefi sabit (kurulum_yazilim=redis etkisiz) ve Docker'ı kurar" {
  krun docker_onizle -e kurulum_yazilim=redis
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.docker_onizle yazilim=docker "* ]] || false
  run lab sh -c '! command -v docker >/dev/null && test ! -e /srv/homelab && echo temiz'
  [ "$output" = temiz ]
  krun docker_kur -e kurulum_yazilim=redis
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.docker_kur yazilim=docker "* ]] || false
  run lab sh -c 'command -v docker >/dev/null && ! command -v redis-server >/dev/null && test ! -e /srv/homelab/redis && echo tamam'
  [ "$output" = tamam ]
  beklenen redis hayir yok yok yok yok
  [ "$(anahtar docker) $(anahtar docker_servis)" = "resmi evet" ]
  krun docker_kur -e kurulum_docker_kaynak=dagitim
  [ "$(recap_changed)" = 0 ]
}

@test "docker_yukselt reddeder ve hiçbir şeyi değiştirmez" {
  once=$(isaret_ozeti; lab dpkg-query -W -f '${Version}' docker-ce)
  krun docker_yukselt
  [ "$status" -ne 0 ]
  [[ "$output" == *"Docker taban yükseltmesi"* ]] || false
  [ "$(isaret_ozeti; lab dpkg-query -W -f '${Version}' docker-ce)" = "$once" ]
}

@test "mariadb_kur (docker): hedef sabit; yeni kurulum iç ağda -> port=ic erisim=ic" {
  krun mariadb_onizle -e kurulum_yazilim=redis -e kurulum_mariadb_mod=docker -e kurulum_mariadb_surum=10.11.19
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.mariadb_onizle yazilim=mariadb mod=docker "* ]] || false
  run lab sh -c 'test ! -e /srv/homelab/mariadb && echo temiz'
  [ "$output" = temiz ]
  krun mariadb_kur -e kurulum_yazilim=redis -e kurulum_mariadb_mod=docker -e kurulum_mariadb_surum=10.11.19
  [ "$status" -eq 0 ]
  beklenen mariadb evet docker ic 10.11.19 ic
  [ "$(anahtar redis_kurulu)" = hayir ]
}

@test "kurulu mariadb: mod verilmeden korunur; farklı mod istenirse reddedilir; erişim uygulanır" {
  krun mariadb_kur -e kurulum_mariadb_surum=10.11.19 -e kurulum_mariadb_erisim=sunucu
  [ "$status" -eq 0 ]
  [[ "$(result)" == *" mod=docker "* ]] || false
  beklenen mariadb evet docker 3306 10.11.19 sunucu
  once=$(isaret_ozeti)
  krun mariadb_kur -e kurulum_mariadb_surum=10.11.19 -e kurulum_mariadb_mod=native
  [ "$status" -ne 0 ]
  [[ "$output" == *"tek mod"* ]] || false
  [ "$(isaret_ozeti)" = "$once" ]
}

@test "mariadb sürümü: mariadb_kur reddeder (mariadb_yukselt der); mariadb_yukselt yükseltir; veri durur" {
  lab sh -c 'docker exec kurulum-mariadb sh -c "mariadb -uroot -p\"\$MARIADB_ROOT_PASSWORD\" -e \"CREATE DATABASE t; CREATE TABLE t.k(a int); INSERT INTO t.k VALUES (42)\""'
  krun mariadb_kur -e kurulum_mariadb_surum=11.4.13
  [ "$status" -ne 0 ]
  [[ "$output" == *"mariadb_yukselt"* ]] || false
  krun mariadb_yukselt -e kurulum_yazilim=redis -e kurulum_mariadb_surum=11.4.13
  [ "$status" -eq 0 ]
  beklenen mariadb evet docker 3306 11.4.13 sunucu
  run lab sh -c 'docker exec kurulum-mariadb sh -c "mariadb -uroot -p\"\$MARIADB_ROOT_PASSWORD\" -N -e \"SELECT a FROM t.k\""'
  [ "$output" = 42 ]
}

@test "redis_kur / redis_yukselt (docker, mod uygulama başına) ve durum; durmuş konteyner = durmus/unknown" {
  krun redis_kur -e kurulum_redis_mod=docker -e kurulum_redis_surum=7.2.17
  [ "$status" -eq 0 ]
  beklenen redis evet docker ic 7.2.17 ic
  krun redis_yukselt -e kurulum_redis_surum=7.4.12 -e kurulum_redis_erisim=agdan
  [ "$status" -eq 0 ]
  beklenen redis evet docker 6379 7.4.12 agdan
  lab docker stop kurulum-redis
  beklenen redis durmus docker unknown 7.4.12 unknown
  # erişim verilmezse (otomatik) iç ağda olmayan kurulu uygulama kurulum_dis_erisim'i izler: varsayılanda 'sunucu'ya döner
  krun redis_kur -e kurulum_redis_surum=7.4.12
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEĞİŞECEK"*"agdan -> sunucu"* ]] || false
  beklenen redis evet docker 6379 7.4.12 sunucu
}

@test "docker hizmeti kapalı: docker_servis=durmus, uygulamalar unknown" {
  lab systemctl stop docker.socket docker
  beklenen mariadb unknown docker unknown unknown unknown
  [ "$(anahtar docker_servis)" = durmus ]
  lab systemctl start docker
  for _ in $(seq 1 40); do [ "$(yayin mariadb)" != "" ] && break; sleep 1; done
  beklenen mariadb evet docker 3306 11.4.13 sunucu
}

@test "uygulama başına mod genel kaldir'da da geçerli; değişken verilmezse eski davranış (genel kurulum_mod) sürer" {
  once=$(isaret_ozeti)
  krun kaldir -e kurulum_yazilim=redis
  [ "$status" -ne 0 ]
  [[ "$output" == *"tek mod"* ]] || false
  [ "$(isaret_ozeti)" = "$once" ]
  krun kaldir -e kurulum_yazilim=redis -e kurulum_redis_mod=native
  [ "$status" -eq 0 ]
  beklenen redis hayir yok yok yok yok
  krun kaldir -e kurulum_yazilim=mariadb -e kurulum_mod=docker
  [ "$status" -eq 0 ]
}

@test "native MariaDB İLK kurulum (paket servisi başlatır): istenen port ve adres GERÇEKTEN uygulanır; ikinci koşu changed=0" {
  lab rm -f /usr/sbin/policy-rc.d      # konteyner imajı servis başlatmayı engeller; gerçek sunucuda paket kurulunca mariadb 127.0.0.1:3306'da BAŞLAR
  krun mariadb_kur -e kurulum_mariadb_port=3307 -e kurulum_mariadb_erisim=agdan
  [ "$status" -eq 0 ]
  [ "$(dinleyen mariadbd)" = "0.0.0.0:3307" ]
  beklenen mariadb evet native 3307 dagitim agdan
  krun mariadb_kur -e kurulum_mariadb_port=3307 -e kurulum_mariadb_erisim=agdan
  [ "$(recap_changed)" = 0 ]
}

@test "native MariaDB: dosya doğru ama servis eski adresteyse önizleme farkı görür, kur uygular; durum dosyaya değil dinleyene bakar" {
  lab sed -i 's/^bind-address = .*/bind-address = 127.0.0.1/' /etc/mysql/mariadb.conf.d/99-kurulum.cnf
  [ "$(dinleyen mariadbd)" = "0.0.0.0:3307" ]
  beklenen mariadb evet native 3307 dagitim agdan
  krun mariadb_onizle -e kurulum_mariadb_port=3307 -e kurulum_mariadb_erisim=sunucu
  [ "$status" -eq 0 ]
  [[ "$(result)" != *" degisen=0 "* ]] || false
  [ "$(dinleyen mariadbd)" = "0.0.0.0:3307" ]
  krun mariadb_kur -e kurulum_mariadb_port=3307 -e kurulum_mariadb_erisim=sunucu
  [ "$status" -eq 0 ]
  [ "$(dinleyen mariadbd)" = "127.0.0.1:3307" ]
  beklenen mariadb evet native 3307 dagitim sunucu
  krun mariadb_kur -e kurulum_mariadb_port=3307 -e kurulum_mariadb_erisim=sunucu
  [ "$(recap_changed)" = 0 ]
}

@test "native MariaDB: istenen adres uygulanamıyorsa koşu BAŞARILI bitmez" {
  lab sh -c 'printf "[mysqld]\nport = 3309\n" > /etc/mysql/mariadb.conf.d/zz-elle.cnf && systemctl restart mariadb'
  [ "$(dinleyen mariadbd)" = "127.0.0.1:3309" ]
  krun mariadb_kur -e kurulum_mariadb_port=3307
  [ "$status" -ne 0 ]
  [[ "$output" == *"istenen dinleme adresi uygulanamadı"* ]] || false
  lab rm /etc/mysql/mariadb.conf.d/zz-elle.cnf
  krun mariadb_kur -e kurulum_mariadb_port=3307
  [ "$status" -eq 0 ]
  [ "$(dinleyen mariadbd)" = "127.0.0.1:3307" ]
}

@test "native MariaDB durdurulunca durmus; mariadb_yukselt native'de reddedilir; mariadb_kur geri açar" {
  lab systemctl stop mariadb
  beklenen mariadb durmus native unknown dagitim unknown
  krun mariadb_yukselt -e kurulum_mariadb_port=3307
  [ "$status" -ne 0 ]
  [[ "$output" == *"native sürüm yükseltme"* ]] || false
  krun mariadb_kur -e kurulum_mariadb_port=3307
  [ "$status" -eq 0 ]
  beklenen mariadb evet native 3307 dagitim sunucu
}

@test "native Redis İLK kurulum: istenen port ve adres uygulanır; parola hiçbir çıktıda yok" {
  krun redis_kur -e kurulum_redis_port=6380 -e kurulum_redis_erisim=agdan
  [ "$status" -eq 0 ]
  [ "$(dinleyen redis-server)" = "0.0.0.0:6380" ]
  beklenen redis evet native 6380 dagitim agdan
  krun redis_kur -e kurulum_redis_port=6380 -e kurulum_redis_erisim=agdan
  [ "$(recap_changed)" = 0 ]
}

@test "native Redis: dosya doğru ama servis eski adresteyse kur uygular" {
  lab sed -i 's/^bind .*/bind 127.0.0.1/' /etc/redis/redis.conf
  [ "$(dinleyen redis-server)" = "0.0.0.0:6380" ]
  krun redis_kur -e kurulum_redis_port=6380 -e kurulum_redis_erisim=sunucu
  [ "$status" -eq 0 ]
  [ "$(dinleyen redis-server)" = "127.0.0.1:6380" ]
  beklenen redis evet native 6380 dagitim sunucu
  krun redis_kur -e kurulum_redis_port=6380 -e kurulum_redis_erisim=sunucu
  [ "$(recap_changed)" = 0 ]
}

@test "nginx aynı değer sözleşmesi: native surum=dagitim; docker iç ağ port=ic" {
  krun nginx_kur -e kurulum_nginx_port=8081
  [ "$status" -eq 0 ]
  beklenen nginx evet native 8081 dagitim sunucu
  krun kaldir -e kurulum_yazilim=nginx -e kurulum_mod=native
  [ "$status" -eq 0 ]
  krun nginx_kur -e kurulum_nginx_mod=docker -e kurulum_nginx_erisim=ic
  [ "$status" -eq 0 ]
  beklenen nginx evet docker ic 1.30.6 ic
}

@test "sonuç satırı sözleşmesi: 20 anahtar, her değer en çok 64 karakter ve yalnız izinli karakterler" {
  krun kurulum_durum
  [ "$(result | tr ' ' '\n' | grep -c '=')" = 20 ]
  run bash -c "printf '%s\n' '$(result)' | tr ' ' '\n' | sed -n 's/^[a-z_]*=//p' | grep -vE '^[A-Za-z0-9_.:+-]{1,64}\$' | wc -l | tr -d ' '"
  [ "$output" = 0 ]
}

@test "PAROLA SIZMIYOR (durum dahil) ve TEMİZ ÇIKTI" {
  krun kurulum_durum -v
  for f in mariadb redis; do
    pw=$(lab sh -c "grep '^[A-Z_]*PASSWORD=' /srv/homelab/$f/.env | cut -d= -f2-")
    [ "${#pw}" -ge 24 ]
    run grep -cF -- "$pw" "$BATS_FILE_TMPDIR/hepsi.log"
    [ "$output" = 0 ]
  done
  run beklenmeyen_uyarilar "$BATS_FILE_TMPDIR/hepsi.log"
  echo "$output" >&3
  [ "$status" -eq 1 ]
}
