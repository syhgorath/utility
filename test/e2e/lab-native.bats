#!/usr/bin/env bats
# LAB e2e (native mod): nginx, mariadb, redis apt paketleri; önizleme hiçbir şey yazmaz, idempotans, yönetilmeyen paket/dolu port koruması,
# dış erişim önerisi (ufw'ye yazılmaz), kaldır veriyi bırakır, native yükseltme yok. SIRALI testler. Gerçek VM yerine GEÇMEZ.
load ortak

setup_file() {
  : > "$BATS_FILE_TMPDIR/hepsi.log"
  "$BATS_TEST_DIRNAME/lab/up.sh" >&3
}

@test "yönetilmeyen (kayıtsız) paket varsa durur ve dokunmaz" {
  lab sh -c 'apt-get install -y -qq redis-server >/dev/null 2>&1'
  krun kur -e kurulum_yazilim=redis
  [ "$status" -ne 0 ]
  [[ "$output" == *"kurulum tarafından yönetilmiyor"* ]]
  run lab sh -c 'dpkg -s redis-server | grep -c "^Status: install ok installed"'
  [ "$output" = 1 ]
  lab sh -c 'systemctl stop redis-server; apt-get remove -y -qq redis-server >/dev/null 2>&1; rm -rf /srv/homelab /etc/kurulum'
}

@test "80 doluyken native nginx kurulmaz (paket kurulum betiği 80'e bağlanır)" {
  lab sh -c 'setsid python3 -m http.server 80 --bind 0.0.0.0 >/dev/null 2>&1 </dev/null &'
  sleep 1
  krun kur -e kurulum_yazilim=nginx -e kurulum_nginx_port=8081
  [ "$status" -ne 0 ]
  [[ "$output" == *"80 şu an dolu"* ]]
  run lab sh -c 'dpkg-query -W nginx 2>&1 | grep -c "no packages found"'
  [ "$output" = 1 ]
  lab sh -c 'pkill -f "[h]ttp.server 80"; true'
}

@test "preview (nginx native) hiçbir şey yazmaz (önce/sonra dosya özeti aynı, paket kurulmaz)" {
  snap='find /srv/homelab /etc/kurulum /etc/nginx /etc/apt -type f 2>/dev/null | sort | xargs -r sha256sum | sha256sum'
  run lab sh -c "$snap"; once=$output
  krun kurulum_onizle -e kurulum_yazilim=nginx
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.kurulum_onizle yazilim=nginx mod=native surum=dagitim port=8080 degisen="* ]]
  run lab sh -c "$snap"
  [ "$output" = "$once" ]
  run lab sh -c '! dpkg -s nginx >/dev/null 2>&1 && echo temiz'
  [ "$output" = temiz ]
}

@test "nginx native: kur (127.0.0.1:8080), 200, ikinci kur changed=0, dağıtım varsayılan sitesi devre dışı" {
  krun kur -e kurulum_yazilim=nginx
  [ "$status" -eq 0 ]
  run lab bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080; printf "GET / HTTP/1.0\r\n\r\n" >&3; head -1 <&3; ss -ltnH | awk "{print \$4}" | grep -c ":80\$" || true; ls /etc/nginx/sites-available/default >/dev/null && echo default-dosyasi-duruyor'
  [[ "${lines[0]}" == *"200"* && "${lines[1]}" = 0 && "${lines[2]}" == default-dosyasi-duruyor ]]
  krun kur -e kurulum_yazilim=nginx
  [ "$(recap_changed)" = 0 ]
}

@test "mariadb native: kur, ikinci kur changed=0, 127.0.0.1:3306, root unix_socket" {
  krun kurulum_onizle -e kurulum_yazilim=mariadb
  [ "$status" -eq 0 ]
  krun kur -e kurulum_yazilim=mariadb
  [ "$status" -eq 0 ]
  [[ "$(result)" == *"yazilim=mariadb mod=native surum=dagitim port=3306 "*"gizli=0" ]]
  krun kur -e kurulum_yazilim=mariadb
  [ "$(recap_changed)" = 0 ]
  run lab sh -c 'ss -ltnH | grep -c "127.0.0.1:3306"; mariadb -uroot -N -e "CREATE DATABASE t; CREATE TABLE t.k(a int); INSERT INTO t.k VALUES (42); SELECT a FROM t.k"'
  [ "${lines[0]}" = 1 ] && [ "${lines[1]}" = 42 ]
}

@test "redis native: parola sunucuda üretilir, NOAUTH, ikinci kur changed=0" {
  krun kur -e kurulum_yazilim=redis
  [ "$status" -eq 0 ]
  [[ "$(result)" == *"yazilim=redis mod=native "*"gizli=1" ]]
  krun kur -e kurulum_yazilim=redis
  [ "$(recap_changed)" = 0 ]
  run lab sh -c '. /dev/null; pw=$(grep "^REDIS_PASSWORD=" /srv/homelab/redis/.env | cut -d= -f2-); stat -c "%a" /srv/homelab/redis/.env; redis-cli ping; redis-cli -a "$pw" --no-auth-warning ping'
  [ "${lines[0]}" = 600 ] && [[ "${lines[1]}" == *NOAUTH* ]] && [ "${lines[2]}" = PONG ]
}

@test "dış erişim: 0.0.0.0'a açar, ufw'ye YAZMAZ, öneri gösterir; kapatınca 127.0.0.1'e döner" {
  krun kur -e kurulum_yazilim=redis -e kurulum_dis_erisim=true
  [ "$status" -eq 0 ]
  [[ "$output" == *"ufw'ye YAZILMAZ"* && "$output" == *"from <yönetim ağı> to any port 6379 proto tcp"* ]]
  run lab sh -c 'ss -ltnH | grep -c "0.0.0.0:6379"; dpkg -s ufw >/dev/null 2>&1 && echo ufw-var || echo ufw-yok'
  [ "${lines[0]}" = 1 ] && [ "${lines[1]}" = ufw-yok ]
  krun kur -e kurulum_yazilim=redis
  run lab sh -c 'ss -ltnH | grep -c "127.0.0.1:6379"'
  [ "$output" = 1 ]
}

@test "native yükseltme v0.1'de yok" {
  krun yukselt -e kurulum_yazilim=mariadb
  [ "$status" -ne 0 ]
  [[ "$output" == *"native sürüm yükseltme v0.1'de yok"* ]]
}

@test "PAROLA SIZMIYOR (native redis)" {
  pw=$(lab sh -c "grep '^REDIS_PASSWORD=' /srv/homelab/redis/.env | cut -d= -f2-")
  [ "${#pw}" -ge 24 ]
  ! grep -qF -- "$pw" "$BATS_FILE_TMPDIR/hepsi.log"
}

@test "KALDIR (native): servis durur, paket purge EDİLMEZ, veri ve yapılandırma kalır" {
  krun kaldir -e kurulum_yazilim=mariadb
  [ "$status" -eq 0 ]
  krun kaldir -e kurulum_yazilim=redis
  [ "$status" -eq 0 ]
  krun kaldir -e kurulum_yazilim=nginx
  [ "$status" -eq 0 ]
  run lab sh -c 'grep -cE "^(NGINX|MARIADB|REDIS)_" /srv/homelab/.env'
  [ "$output" = 0 ]
  run lab sh -c 'test -d /var/lib/mysql/t && echo mysql-veri; test -f /etc/redis/redis.conf && echo redis-conf; test -f /etc/nginx/nginx.conf && echo nginx-conf; test -d /var/lib/redis && echo redis-veri; ss -ltnH | grep -cE ":(8080|3306|6379) " || true'
  [[ "$output" == *mysql-veri* && "$output" == *redis-conf* && "$output" == *nginx-conf* && "$output" == *redis-veri* ]]
  [ "${lines[${#lines[@]}-1]}" = 0 ]
  krun kaldir -e kurulum_yazilim=mariadb
  [ "$(recap_changed)" = 0 ]
}

@test "durum (native karışık) ve TEMİZ ÇIKTI: hiçbir koşuda beklenmeyen [WARNING] / [DEPRECATION WARNING] yok" {
  krun kurulum_durum
  [ "$status" -eq 0 ]
  run beklenmeyen_uyarilar "$BATS_FILE_TMPDIR/hepsi.log"
  echo "$output" >&3
  [ "$status" -eq 1 ]
}
