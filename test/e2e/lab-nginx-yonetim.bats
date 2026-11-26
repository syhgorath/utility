#!/usr/bin/env bats
# LAB e2e: iki yönetim hatasının gerileme testleri. İşaret dosyasına güvenilmez; SUNUCUDAKİ gerçek durum (ss, docker, HTTP) denetlenir. SIRALI testler.
#   H1: native nginx aynı portta dış erişim değişikliği uygulanmıyordu (reload "Address already in use"; kapatılan port açık kalıyordu).
#   H2: docker `yukselt` port denetimi yapmıyordu; dolu portta nginx kapalı kalıyordu.
# Gerçek VM yerine GEÇMEZ. Ağda TLS'i araya giren yazılım varsa: LAB_CA_FILE=<kök sertifika.pem>
# DİKKAT: macOS bash 3.2 ile bats, testin ortasındaki başarısız [[ ]] ifadesini YOK SAYAR; bu yüzden her [[ ]] "|| false" ile biter.
load ortak

D=(-e kurulum_yazilim=nginx -e kurulum_mod=docker)
N=(-e kurulum_yazilim=nginx -e kurulum_mod=native)
ACIK=(-e kurulum_dis_erisim=true)
KAPALI=(-e kurulum_dis_erisim=false)

# <port> dinleyen adresleri: "127.0.0.1:8081" ya da "" (boşlukla birleşik, sıralı)
dinleyen() { lab sh -c "ss -ltnH | awk '{print \$4}' | grep -E ':$1\$' | sort | tr '\n' ' ' | sed 's/ \$//'"; }
lab_ip() { lab hostname -I | awk '{print $1}'; }
# http <adres> <port>: GET / durum satırı (erişilemezse boş)
http() { lab timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2 && printf 'GET / HTTP/1.0\r\n\r\n' >&3 && head -n1 <&3" 2>/dev/null | tr -d '\r'; }
# docker nginx'e dokunulmadığının kanıtı: dosyalar, konteyner kimliği ve başlama anı, yedek klasörü
docker_ozeti() { lab sh -c 'sha256sum /srv/homelab/nginx/compose.yml /srv/homelab/.env /srv/homelab/.kurulum; docker inspect -f "{{.Id}} {{.State.StartedAt}} {{.State.Running}}" kurulum-nginx; ls /srv/homelab/nginx/yedek 2>/dev/null || true'; }
nginx_ana_pid() { lab systemctl show -p MainPID --value nginx; }
isaret_bind() { lab python3 -c 'import json; print(json.load(open("/srv/homelab/.kurulum"))["yazilimlar"]["nginx"]["bind"])'; }

setup_file() {
  : > "$BATS_FILE_TMPDIR/hepsi.log"
  "$BATS_TEST_DIRNAME/lab/up.sh" >&3
}

@test "hazırlık: docker taban + nginx docker (127.0.0.1:8081) + durdurulmuş redis docker (6379 kayıtlı)" {
  krun kur -e kurulum_yazilim=docker
  [ "$status" -eq 0 ]
  krun kur "${D[@]}" -e kurulum_nginx_port=8081
  [ "$status" -eq 0 ]
  krun kur -e kurulum_yazilim=redis -e kurulum_mod=docker -e kurulum_redis_erisim=sunucu   # kayıtlı port gerekir (otomatik = iç ağ, port kaydedilmez)
  [ "$status" -eq 0 ]
  lab docker stop kurulum-redis
  [ "$(dinleyen 6379)" = "" ]
  [ "$(dinleyen 8081)" = "127.0.0.1:8081" ]
}

@test "H2: yukselt, başka sürecin dinlediği portu HİÇBİR ŞEY durdurmadan reddeder" {
  docker exec -d kurulum-lab python3 -m http.server 8090 --bind 127.0.0.1
  sleep 1
  once=$(docker_ozeti)
  krun yukselt "${D[@]}" -e kurulum_nginx_port=8090 -e kurulum_nginx_surum=1.31.8
  [ "$status" -ne 0 ]
  [[ "$(http 127.0.0.1 8081)" == *" 200 "* ]] || false
  [ "$(docker_ozeti)" = "$once" ]
  [[ "$output" == *"8090 portunu sunucuda başka bir süreç dinliyor"* ]] || false
}

@test "H2: yukselt, başka uygulamaya kayıtlı portu (durmuş olsa bile) HİÇBİR ŞEY durdurmadan reddeder" {
  once=$(docker_ozeti)
  krun yukselt "${D[@]}" -e kurulum_nginx_port=6379 -e kurulum_nginx_surum=1.31.8
  [ "$status" -ne 0 ]
  [[ "$(http 127.0.0.1 8081)" == *" 200 "* ]] || false
  [ "$(docker_ozeti)" = "$once" ]
  [[ "$output" == *"6379 portu redis uygulamasına verilmiş"* ]] || false
}

@test "H2: yukselt kendi portunda çalışmaya devam eder (1.30.6 -> 1.31.8)" {
  krun yukselt "${D[@]}" -e kurulum_nginx_port=8081 -e kurulum_nginx_surum=1.31.8
  [ "$status" -eq 0 ]
  [ "$(lab docker inspect -f '{{.Config.Image}}' kurulum-nginx)" = "nginx:1.31.8" ]
  [[ "$(http 127.0.0.1 8081)" == *" 200 "* ]] || false
}

@test "H1 hazırlık: docker nginx kaldırılır, native nginx 127.0.0.1:8081" {
  krun kaldir "${D[@]}"
  [ "$status" -eq 0 ]
  krun kur "${N[@]}" -e kurulum_nginx_port=8081
  [ "$status" -eq 0 ]
  [ "$(dinleyen 8081)" = "127.0.0.1:8081" ]
}

@test "H1: aynı portta dış erişim AÇMA uygulanır; ikinci kur changed=0" {
  krun kur "${N[@]}" -e kurulum_nginx_port=8081 "${ACIK[@]}"
  [ "$status" -eq 0 ]
  [ "$(dinleyen 8081)" = "0.0.0.0:8081" ]
  [[ "$(http "$(lab_ip)" 8081)" == *" 200 "* ]] || false
  krun kur "${N[@]}" -e kurulum_nginx_port=8081 "${ACIK[@]}"
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
}

@test "H1 (güvenlik): aynı portta dış erişim KAPATMA uygulanır; dış adresten erişilemez; ikinci kur changed=0" {
  lab systemctl restart nginx          # başlangıç: gerçekten dışarı açık
  [ "$(dinleyen 8081)" = "0.0.0.0:8081" ]
  krun kur "${N[@]}" -e kurulum_nginx_port=8081 "${KAPALI[@]}"
  [ "$status" -eq 0 ]
  [ "$(dinleyen 8081)" = "127.0.0.1:8081" ]
  [ "$(http "$(lab_ip)" 8081)" = "" ]
  krun kur "${N[@]}" -e kurulum_nginx_port=8081 "${KAPALI[@]}"
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
}

@test "H1: eski hatadan ETKİLENMİŞ sunucu (dosya 'kapalı', servis açık): önizleme farkı görür, kur kapatır" {
  krun kur "${N[@]}" -e kurulum_nginx_port=8081 "${ACIK[@]}"
  lab systemctl restart nginx
  # eski paketin bıraktığı durum: site dosyası 127.0.0.1, çalışan süreç hâlâ 0.0.0.0
  lab sed -i 's/listen 0.0.0.0:8081/listen 127.0.0.1:8081/' /etc/nginx/sites-available/kurulum
  [ "$(dinleyen 8081)" = "0.0.0.0:8081" ]
  pid=$(nginx_ana_pid)
  krun kurulum_onizle "${N[@]}" -e kurulum_nginx_port=8081 "${KAPALI[@]}"
  [ "$status" -eq 0 ]
  [[ "$(result)" != *" degisen=0 "* ]] || false
  [ "$(nginx_ana_pid)" = "$pid" ]                 # önizleme servise dokunmaz
  [ "$(dinleyen 8081)" = "0.0.0.0:8081" ]
  krun kur "${N[@]}" -e kurulum_nginx_port=8081 "${KAPALI[@]}"
  [ "$status" -eq 0 ]
  [ "$(dinleyen 8081)" = "127.0.0.1:8081" ]
  [ "$(http "$(lab_ip)" 8081)" = "" ]
  [[ "$(result)" != *" degisen=0 "* ]] || false
  krun kur "${N[@]}" -e kurulum_nginx_port=8081 "${KAPALI[@]}"
  [ "$(recap_changed)" = 0 ]
}

@test "H1: istenen adres uygulanamıyorsa kur BAŞARILI bitmez ve her koşuda yeniden hata verir" {
  lab sh -c 'printf "server { listen 0.0.0.0:8081; }\n" > /etc/nginx/conf.d/elle.conf && systemctl restart nginx'
  [ "$(dinleyen 8081)" = "0.0.0.0:8081" ]
  for _ in 1 2; do
    krun kur "${N[@]}" -e kurulum_nginx_port=8081 "${KAPALI[@]}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"istenen dinleme adresi uygulanamadı"* ]] || false
  done
  lab sh -c 'rm /etc/nginx/conf.d/elle.conf'
  krun kur "${N[@]}" -e kurulum_nginx_port=8081 "${KAPALI[@]}"
  [ "$status" -eq 0 ]
  [ "$(dinleyen 8081)" = "127.0.0.1:8081" ]
  [ "$(isaret_bind)" = "127.0.0.1" ]
}

@test "H1: port değişimi eskisi gibi reload ile (ana süreç aynı), eski port kapanır" {
  pid=$(nginx_ana_pid)
  krun kur "${N[@]}" -e kurulum_nginx_port=8082
  [ "$status" -eq 0 ]
  [ "$(dinleyen 8082)" = "127.0.0.1:8082" ]
  [ "$(dinleyen 8081)" = "" ]
  [ "$(nginx_ana_pid)" = "$pid" ]
}

@test "H1: durdurulmuş nginx kur ile istenen adreste başlar" {
  lab systemctl stop nginx
  krun kur "${N[@]}" -e kurulum_nginx_port=8082
  [ "$status" -eq 0 ]
  [ "$(dinleyen 8082)" = "127.0.0.1:8082" ]
}

@test "H1: temiz native kurulum 80 portunda yalnız 127.0.0.1 dinler (paketin varsayılan sitesi 0.0.0.0'da açar)" {
  krun kaldir "${N[@]}" -e kurulum_nginx_port=8082
  [ "$status" -eq 0 ]
  lab sh -c 'apt-get purge -y -qq nginx nginx-common >/dev/null 2>&1; rm -rf /etc/nginx'
  lab rm -f /usr/sbin/policy-rc.d      # konteyner imajı servis başlatmayı engeller; gerçek sunucuda paket kurulunca nginx 0.0.0.0:80'de BAŞLAR
  krun kurulum_onizle "${N[@]}" -e kurulum_nginx_port=80
  [ "$status" -eq 0 ]
  krun kur "${N[@]}" -e kurulum_nginx_port=80
  [ "$status" -eq 0 ]
  [ "$(dinleyen 80)" = "127.0.0.1:80" ]
  [ "$(http "$(lab_ip)" 80)" = "" ]
  krun kur "${N[@]}" -e kurulum_nginx_port=80
  [ "$(recap_changed)" = 0 ]
}

@test "TEMİZ ÇIKTI: hiçbir koşuda [WARNING] / [DEPRECATION WARNING] yok" {
  run grep -nE '\[(DEPRECATION )?WARNING\]' "$BATS_FILE_TMPDIR/hepsi.log"
  echo "$output" >&3
  [ "$status" -eq 1 ]
}
