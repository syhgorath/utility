#!/usr/bin/env bats
# LAB e2e (docker modu): Docker taban + nginx + mariadb + redis; idempotans, yükseltme (veri duruyor mu), kaldır (veri kalıyor), parola sızıntısı,
# port çakışması, ana klasör uyuşmazlığı. SIRALI testler. Gereken: docker (Colima), .venv. Konteyner BAŞTAN kurulur; gerçek VM yerine GEÇMEZ.
# Ağda TLS'i araya giren yazılım varsa: LAB_CA_FILE=<kök sertifika.pem> (yalnızca LAB konteynerine eklenir).
load ortak

setup_file() {
  : > "$BATS_FILE_TMPDIR/hepsi.log"
  "$BATS_TEST_DIRNAME/lab/up.sh" >&3
}

@test "durum: salt okunur; ana klasör yeni, Docker yok" {
  krun kurulum_durum
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
  [ "$(result)" = "SSHPOCKET_RESULT utility.kurulum_durum ana_durum=yeni docker=yok kurulu=yok portlar=yok nginx_kurulu=hayir mariadb_kurulu=hayir redis_kurulu=hayir proxy_kurulu=hayir docker_kurulu=hayir docker_servis=yok" ]
}

@test "Docker yokken docker modu durur ve HİÇBİR ŞEY oluşturmaz" {
  krun kur -e kurulum_yazilim=nginx -e kurulum_mod=docker
  [ "$status" -ne 0 ]
  [[ "$output" == *"docker modu için uygun Docker yok"* ]]
  run lab sh -c 'test ! -e /srv/homelab && test ! -e /etc/kurulum && echo temiz'
  [ "$output" = temiz ]
}

@test "preview (Docker taban): hiçbir şey yazmaz" {
  krun kurulum_onizle -e kurulum_yazilim=docker
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.kurulum_onizle yazilim=docker mod=native surum=resmi port=0 degisen="* ]]
  run lab sh -c 'test ! -e /srv/homelab && test ! -e /etc/apt/sources.list.d/docker.sources && ! command -v docker && echo temiz'
  [ "$output" = temiz ]
}

@test "kur docker taban (resmi apt deposu): Docker çalışır, kullanıcı docker grubuna eklenmez" {
  krun kur -e kurulum_yazilim=docker
  [ "$status" -eq 0 ]
  run lab sh -c 'docker run --rm hello-world 2>/dev/null | grep -c "Hello from Docker"; id -nG tester | grep -c docker || true; dpkg -s docker-ce | sed -n "s/^Version: //p"'
  [[ "${lines[0]}" = 1 && "${lines[1]}" = 0 && "${lines[2]}" == 5:* ]]
}

@test "ikinci kur docker changed=0 (idempotans) ve kurulu Docker'a dokunmaz" {
  krun kur -e kurulum_yazilim=docker
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
  [[ "$(result)" == *"degisen=0 "* ]]
}

@test "nginx docker: kur, 200 döner, ikinci kur changed=0, port 127.0.0.1" {
  krun kurulum_onizle -e kurulum_yazilim=nginx -e kurulum_mod=docker
  [ "$status" -eq 0 ]
  run lab sh -c 'test ! -e /srv/homelab/nginx && echo temiz'; [ "$output" = temiz ]
  krun kur -e kurulum_yazilim=nginx -e kurulum_mod=docker
  [ "$status" -eq 0 ]
  [ "$(result)" = "SSHPOCKET_RESULT utility.kur yazilim=nginx mod=docker surum=1.30.6 port=8080 degisen=$(grep -o 'degisen=[0-9]*' <<<"$(result)" | cut -d= -f2) yukseltme=hayir gizli=0" ]
  run lab bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080; printf "GET / HTTP/1.0\r\n\r\n" >&3; head -1 <&3; docker ps --format "{{.Ports}}"'
  [[ "${lines[0]}" == *"200"* && "${lines[1]}" == "127.0.0.1:8080->80/tcp" ]]
  krun kur -e kurulum_yazilim=nginx -e kurulum_mod=docker
  [ "$(recap_changed)" = 0 ]
}

@test "mariadb docker 10.11.19: kur, parola sunucuda 0600, ikinci kur changed=0, veri yazılır" {
  krun kur -e kurulum_yazilim=mariadb -e kurulum_mod=docker -e kurulum_mariadb_surum=10.11.19 -e kurulum_mariadb_erisim=sunucu   # yeni docker kurulumu otomatik=iç ağ; bu testler yayınlı kurulumu sınar
  [ "$status" -eq 0 ]
  [[ "$(result)" == *"yazilim=mariadb mod=docker surum=10.11.19 port=3306 "*"gizli=1" ]]
  run lab sh -c 'stat -c "%a" /srv/homelab/mariadb/.env; grep -c "^MARIADB_ROOT_PASSWORD=" /srv/homelab/mariadb/.env'
  [ "${lines[0]}" = 600 ] && [ "${lines[1]}" = 1 ]
  krun kur -e kurulum_yazilim=mariadb -e kurulum_mod=docker -e kurulum_mariadb_surum=10.11.19
  [ "$(recap_changed)" = 0 ]
  run lab sh -c 'docker exec kurulum-mariadb sh -c "mariadb -uroot -p\"\$MARIADB_ROOT_PASSWORD\" -e \"CREATE DATABASE t; CREATE TABLE t.k(a int); INSERT INTO t.k VALUES (42)\""'
  [ "$status" -eq 0 ]
}

@test "kur sürümü sessizce değiştirmez; preview yukseltme=evet der" {
  krun kur -e kurulum_yazilim=mariadb -e kurulum_mod=docker -e kurulum_mariadb_surum=11.4.13
  [ "$status" -ne 0 ]
  [[ "$output" == *"kur sürümü sessizce değiştirmez"* ]]
  krun kurulum_onizle -e kurulum_yazilim=mariadb -e kurulum_mod=docker -e kurulum_mariadb_surum=11.4.13
  [ "$status" -eq 0 ]
  [[ "$(result)" == *"surum=11.4.13"*"yukseltme=evet"* ]]
}

@test "YÜKSELTME: mariadb 10.11.19 -> 11.4.13: döküm 0600/0700, veri duruyor, sonra tekrar kur changed=0" {
  krun yukselt -e kurulum_yazilim=mariadb -e kurulum_mod=docker -e kurulum_mariadb_surum=11.4.13
  [ "$status" -eq 0 ]
  run lab sh -c 'stat -c "%a" /srv/homelab/mariadb/yedek /srv/homelab/mariadb/yedek/*/dump.sql | tr "\n" " "; docker exec kurulum-mariadb sh -c "mariadb -uroot -p\"\$MARIADB_ROOT_PASSWORD\" -N -e \"SELECT a FROM t.k; SELECT version()\"" | tr "\n" " "'
  [[ "$output" == "700 600 42 11.4.13-MariaDB"* ]]
  krun kur -e kurulum_yazilim=mariadb -e kurulum_mod=docker -e kurulum_mariadb_surum=11.4.13
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
}

@test "geri düşürme reddedilir (yukselt yalnızca daha yeni sürüme)" {
  krun yukselt -e kurulum_yazilim=mariadb -e kurulum_mod=docker -e kurulum_mariadb_surum=10.11.19
  [ "$status" -ne 0 ]
  run lab sh -c 'docker exec kurulum-mariadb sh -c "mariadb -uroot -p\"\$MARIADB_ROOT_PASSWORD\" -N -e \"SELECT a FROM t.k\""'
  [ "$output" = 42 ]
}

@test "redis docker 7.2.17: kur, ikinci kur changed=0; YÜKSELTME 7.4.12: anahtar duruyor" {
  krun kur -e kurulum_yazilim=redis -e kurulum_mod=docker -e kurulum_redis_surum=7.2.17 -e kurulum_redis_erisim=sunucu
  [ "$status" -eq 0 ]
  krun kur -e kurulum_yazilim=redis -e kurulum_mod=docker -e kurulum_redis_surum=7.2.17
  [ "$(recap_changed)" = 0 ]
  lab sh -c 'docker exec kurulum-redis sh -c "redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning SET k v"'
  krun yukselt -e kurulum_yazilim=redis -e kurulum_mod=docker -e kurulum_redis_surum=7.4.12
  [ "$status" -eq 0 ]
  run lab sh -c 'docker exec kurulum-redis sh -c "redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning GET k"'
  [ "$output" = v ]
}

@test "nginx docker yükseltme 1.30.6 -> 1.31.8: web kökü yedeği alınır, sayfa duruyor" {
  lab sh -c 'echo OZEL > /srv/homelab/nginx/data/www/ozel.html'
  krun yukselt -e kurulum_yazilim=nginx -e kurulum_mod=docker -e kurulum_nginx_surum=1.31.8
  [ "$status" -eq 0 ]
  run lab sh -c 'tar tzf /srv/homelab/nginx/yedek/*/www.tar.gz | grep -c ozel.html; docker ps --format "{{.Image}}" | grep nginx'
  [ "${lines[0]}" = 1 ] && [ "${lines[1]}" = "nginx:1.31.8" ]
}

@test "port çakışması: başkasına verilmiş port reddedilir ve boş port önerilir" {
  krun kurulum_onizle -e kurulum_yazilim=redis -e kurulum_mod=docker -e kurulum_redis_surum=7.4.12 -e kurulum_redis_port=3306
  [ "$status" -ne 0 ]
  [[ "$output" == *"3306 portu mariadb uygulamasına verilmiş"* && "$output" == *"Boş port önerisi: 3307"* ]]
}

@test "bir yazılım için tek mod: docker kurulu yazılım native istenince durur" {
  krun kurulum_onizle -e kurulum_yazilim=nginx -e kurulum_mod=native
  [ "$status" -ne 0 ]
  [[ "$output" == *"tek mod"* ]]
}

@test "ana klasör uyuşmazlığı: sunucudaki kaynaktır; durur, yerelde yeni klasör açmaz" {
  krun kurulum_durum -e kurulum_ana_klasor=/srv/baska
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.kurulum_durum ana_durum=uyusmuyor "* ]]
  krun kur -e kurulum_yazilim=nginx -e kurulum_mod=docker -e kurulum_ana_klasor=/srv/baska
  [ "$status" -ne 0 ]
  [[ "$output" == *"ana klasör sunucuda /srv/homelab, yerelde /srv/baska"* ]]
  run lab sh -c 'test ! -e /srv/baska && echo temiz'; [ "$output" = temiz ]
}

@test "yasak ana klasör yolu reddedilir" {
  for p in / /etc /usr/local/x "/srv/a b" ../x /var/lib/docker/x; do
    krun kurulum_durum -e "{\"kurulum_ana_klasor\":\"$p\"}"
    [ "$status" -ne 0 ]
  done
}

@test "aynı anda ikinci koşu kilitte durur" {
  lab sh -c 'setsid bash -c "exec 9>/run/kurulum.lock; flock -n 9; echo \$\$ > /run/kurulum.lock.pid; exec sleep 120" </dev/null >/dev/null 2>&1 &'
  sleep 1
  krun kur -e kurulum_yazilim=docker
  [ "$status" -ne 0 ]
  [[ "$output" == *"kilit başka bir koşuda"* ]]
  lab sh -c 'kill -- -$(cat /run/kurulum.lock.pid); rm -f /run/kurulum.lock.pid'
  krun kur -e kurulum_yazilim=docker
  [ "$status" -eq 0 ]
}

@test "KALDIR: konteyner gider, veri/.env/compose kalır; yeniden kur veriyi bulur" {
  krun kaldir -e kurulum_yazilim=mariadb -e kurulum_mod=docker -e kurulum_mariadb_surum=11.4.13
  [ "$status" -eq 0 ]
  # V02: ortak .env'de kaldırılan uygulamanın bağlantı anahtarları temizlenir, diğerlerinin kalır; gizli .env (parola) kalır
  run lab sh -c 'grep -c "^MARIADB_" /srv/homelab/.env; grep -c "^NGINX_" /srv/homelab/.env; grep -c "^MARIADB_ROOT_PASSWORD=" /srv/homelab/mariadb/.env'
  [ "${lines[0]}" = 0 ] && [ "${lines[1]}" = 3 ] && [ "${lines[2]}" = 1 ]
  run lab sh -c 'docker ps -a --format "{{.Names}}" | grep -c mariadb; test -d /srv/homelab/mariadb/data/t && test -f /srv/homelab/mariadb/.env && test -f /srv/homelab/mariadb/compose.yml && echo kaldi'
  [ "${lines[0]}" = 0 ] && [ "${lines[1]}" = kaldi ]
  krun kaldir -e kurulum_yazilim=mariadb -e kurulum_mod=docker -e kurulum_mariadb_surum=11.4.13
  [ "$(recap_changed)" = 0 ]
  krun kur -e kurulum_yazilim=mariadb -e kurulum_mod=docker -e kurulum_mariadb_surum=11.4.13 -e kurulum_mariadb_erisim=sunucu   # kaldır sonrası yeniden kurulum "yeni" sayılır
  [ "$status" -eq 0 ]
  [[ "$(result)" == *"gizli=0" ]]
  run lab sh -c 'grep -c "^MARIADB_" /srv/homelab/.env'
  [ "$output" = 3 ]
  run lab sh -c 'docker exec kurulum-mariadb sh -c "mariadb -uroot -p\"\$MARIADB_ROOT_PASSWORD\" -N -e \"SELECT a FROM t.k\""'
  [ "$output" = 42 ]
}

@test "PAROLA SIZMIYOR: hiçbir koşu ekranında üretilen parolalar yok (-v dahil)" {
  krun kur -v -e kurulum_yazilim=redis -e kurulum_mod=docker -e kurulum_redis_surum=7.4.12
  for f in mariadb redis; do
    pw=$(lab sh -c "grep '^[A-Z_]*PASSWORD=' /srv/homelab/$f/.env | cut -d= -f2-")
    [ "${#pw}" -ge 24 ]
    ! grep -qF -- "$pw" "$BATS_FILE_TMPDIR/hepsi.log"
  done
  # sonuç satırları anahtar adı/sayı yazar, değer yazmaz
  ! grep -E 'SSHPOCKET_RESULT.*(PASSWORD|parola|password)' "$BATS_FILE_TMPDIR/hepsi.log"
}

@test "durum: kurulu yazılımlar ve portlar" {
  krun kurulum_durum
  [ "$status" -eq 0 ]
  [ "$(result)" = "SSHPOCKET_RESULT utility.kurulum_durum ana_durum=tamam docker=resmi kurulu=docker:native+mariadb:docker+nginx:docker+redis:docker portlar=mariadb:3306+nginx:8080+redis:6379 nginx_kurulu=evet mariadb_kurulu=evet redis_kurulu=evet proxy_kurulu=hayir docker_kurulu=evet docker_servis=evet" ]
  krun nginx_durum
  [ "$(result)" = "SSHPOCKET_RESULT utility.nginx_durum ana_durum=tamam nginx_kurulu=evet nginx_mod=docker nginx_port=8080 nginx_surum=1.31.8 nginx_erisim=sunucu nginx_duvar=gerekmez nginx_duvar_engel=hayir" ]
  krun mariadb_durum
  [ "$(result)" = "SSHPOCKET_RESULT utility.mariadb_durum ana_durum=tamam mariadb_kurulu=evet mariadb_mod=docker mariadb_port=3306 mariadb_surum=11.4.13 mariadb_erisim=sunucu mariadb_duvar=gerekmez mariadb_duvar_engel=hayir" ]
  krun redis_durum
  [ "$(result)" = "SSHPOCKET_RESULT utility.redis_durum ana_durum=tamam redis_kurulu=evet redis_mod=docker redis_port=6379 redis_surum=7.4.12 redis_erisim=sunucu redis_duvar=gerekmez redis_duvar_engel=hayir" ]
}

@test "TEMİZ ÇIKTI: hiçbir koşuda beklenmeyen [WARNING] / [DEPRECATION WARNING] yok" {
  run beklenmeyen_uyarilar "$BATS_FILE_TMPDIR/hepsi.log"
  echo "$output" >&3
  [ "$status" -eq 1 ]
}
