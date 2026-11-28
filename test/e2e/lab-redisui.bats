#!/usr/bin/env bats
# LAB e2e: Redis Insight (redisui_onizle, redisui_kur, redisui_yukselt, redisui_durum, kaldir): docker Redis ön koşulu, erişim (ic | sunucu), ortak ağdan
# konteyner adıyla erişim, parola ve şifreleme anahtarının gizliliği. KOŞULLAR KABUL EDİLMEZ: yalnız ayarlar ve bağlantı listesi OKUNUR.
# İmajlar internetten indirilir. SIRALI testler. Gerçek VM yerine GEÇMEZ. Ağda TLS'i araya giren yazılım varsa: LAB_CA_FILE=<kök sertifika.pem>
# DİKKAT: macOS bash 3.2 ile bats, testin ortasındaki başarısız [[ ]] ifadesini YOK SAYAR; bu yüzden her [[ ]] "|| false" ile biter.
# shellcheck disable=SC2016  # tek tırnak içindeki $ ifadeleri bilerek sunucuda genişler
load ortak

anahtar() { local v; v=$(result | tr ' ' '\n' | sed -n "s/^$1=//p"); echo "${v:--}"; }
# ri_beklenen <kurulu> <mod> <port> <surum> <erisim> <hedef>
ri_beklenen() {
  krun redisui_durum
  [ "$status" -eq 0 ] || return 1
  [ "$(recap_changed)" = 0 ] || return 1
  local g
  g="SSHPOCKET_RESULT utility.redisui_durum ana_durum=$(anahtar ana_durum) redisui_kurulu=$1 redisui_mod=$2 redisui_port=$3 redisui_surum=$4 redisui_erisim=$5 redisui_hedef=$6"
  [ "$(result)" = "$g" ] || { echo "beklenen: $g"; echo "gelen:    $(result)"; return 1; } >&2
}
HEDEF=kurulum-redisui:5540
yayin() { lab docker port kurulum-redisui 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
kimlik() { lab docker inspect -f '{{.Id}} {{.State.StartedAt}}' kurulum-redisui; }
ozet() { lab sh -c 'sha256sum /srv/homelab/.kurulum /srv/homelab/.env /srv/homelab/redisui/.env /srv/homelab/redisui/compose.yml 2>/dev/null; docker ps -a --format "{{.Names}} {{.Image}}" | sort'; }
yazilmadi() { lab sh -c 'test ! -e /srv/homelab/redisui && ! docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q kurulum-redisui && echo temiz'; }
# değerin kendisi hiçbir yerde yazdırılmaz: yalnız özet ya da eşitlik
anahtar_ozeti() { lab sh -c "grep '^RI_ENCRYPTION_KEY=' /srv/homelab/redisui/.env | sha256sum"; }
parolalar_esit() { lab sh -c 'a=$(sed -n s/^REDIS_PASSWORD=//p /srv/homelab/redis/.env); b=$(sed -n s/^RI_REDIS_PASSWORD=//p /srv/homelab/redisui/.env); [ -n "$a" ] && [ "$a" = "$b" ] && echo esit || echo FARKLI'; }
# Redis Insight konteynerinin KENDİ ortam değişkenleriyle Redis'e kimlik doğrulaması (bağlantı bilgisi doğru mu)
baglanti_dene() {
  lab docker exec kurulum-redisui node -e 'const p = process.env.RI_REDIS_PASSWORD || ""; const s = require("net").connect(Number(process.env.RI_REDIS_PORT), process.env.RI_REDIS_HOST, () => s.write("*2\r\n$4\r\nAUTH\r\n$" + Buffer.byteLength(p) + "\r\n" + p + "\r\n")); s.setTimeout(5000, () => process.exit(2)); s.on("error", () => process.exit(3)); s.on("data", d => { console.log(String(d).trim()); process.exit(0); });'
}
# ortak ağdaki BAŞKA bir konteynerden (redis) konteyner adıyla arayüz
adla_erisim() { lab docker exec kurulum-redis bash -c 'exec 3<>/dev/tcp/kurulum-redisui/5540 && printf "GET /api/health/ HTTP/1.0\r\nHost: kurulum-redisui\r\n\r\n" >&3 && cat <&3'; }
# LAB sunucusunun DIŞINDAN (ayrı konteyner) ve sunucunun kendi 127.0.0.1'inden porta TCP bağlantısı
disaridan() {
  local ip img
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' kurulum-lab)
  img=$(docker inspect -f '{{.Config.Image}}' kurulum-lab)
  docker run --rm --entrypoint timeout "$img" 5 bash -c "</dev/tcp/$ip/5540" 2>/dev/null
}
sunucudan() { lab curl -fsS -m 5 http://127.0.0.1:5540/api/health/; }
api() { lab sh -c "curl -fsS -m 10 http://\$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' kurulum-redisui):5540$1"; }

setup_file() {
  : > "$BATS_FILE_TMPDIR/hepsi.log"
  "$BATS_TEST_DIRNAME/lab/up.sh" >&3
  docker exec kurulum-lab sh -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y -q curl >/dev/null 2>&1'
}

@test "temiz sunucu: redisui yok; genel özet redisui_kurulu=hayir" {
  ri_beklenen hayir yok yok yok yok yok
  krun kurulum_durum
  [ "$(anahtar redisui_kurulu)" = hayir ]
}

@test "Docker yokken redisui_onizle ve redisui_kur açık mesajla durur, hiçbir şey yazmaz" {
  for e in redisui_onizle redisui_kur; do
    krun "$e"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"Docker taban kurulumunu"* || "$output" == *"Bu paketle kurulu Redis yok"* ]] || return 1
  done
  run lab sh -c 'test ! -e /srv/homelab && test ! -e /etc/kurulum && ! command -v docker >/dev/null && echo temiz'
  [ "$output" = temiz ]
}

@test "Redis yokken durur, hiçbir şey yazmaz" {
  krun docker_kur
  [ "$status" -eq 0 ]
  once=$(ozet)
  for e in redisui_onizle redisui_kur; do
    krun "$e"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"Bu paketle kurulu Redis yok"* && "$output" == *"Hiçbir şey değiştirilmedi"* ]] || return 1
  done
  [ "$(ozet)" = "$once" ]
  [ "$(yazilmadi)" = temiz ]
}

@test "Redis native iken durur, hiçbir şey yazmaz" {
  krun redis_kur -e kurulum_redis_mod=native
  [ "$status" -eq 0 ]
  once=$(ozet)
  for e in redisui_onizle redisui_kur; do
    krun "$e"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"Sunucudaki Redis native kurulu"* ]] || return 1
  done
  [ "$(ozet)" = "$once" ]
  [ "$(yazilmadi)" = temiz ]
  krun kaldir -e kurulum_yazilim=redis
  [ "$status" -eq 0 ]
  krun redis_kur -e kurulum_redis_mod=docker
  [ "$status" -eq 0 ]
}

@test "ağa açma ve bilinmeyen sürüm reddedilir (agdan, otomatik, listede olmayan sürüm)" {
  for a in kurulum_redisui_erisim=agdan kurulum_redisui_erisim=otomatik kurulum_redisui_surum=3.8.0; do
    krun redisui_kur -e "$a"
    [ "$status" -ne 0 ] || return 1
  done
  [ "$(yazilmadi)" = temiz ]
}

@test "redisui_onizle yazmaz; redisui_kur (varsayılan ic, 3.10.1): gizli değerler 0600 .env'de, compose'da yok, port yayınlanmaz" {
  once=$(ozet)
  krun redisui_onizle -e kurulum_redisui_surum=3.10.1 -e kurulum_yazilim=nginx -e kurulum_mod=native -e kurulum_dis_erisim=true
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.redisui_onizle yazilim=redisui mod=docker surum=3.10.1 port=0 "* ]] || false
  [ "$(ozet)" = "$once" ]
  [ "$(yazilmadi)" = temiz ]
  krun redisui_kur -e kurulum_redisui_surum=3.10.1 -e kurulum_yazilim=nginx -e kurulum_mod=native -e kurulum_dis_erisim=true
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.redisui_kur yazilim=redisui mod=docker surum=3.10.1 port=0 "*" gizli=1" ]] || false
  [[ "$output" == *"KENDİ GİRİŞİ YOKTUR"* && "$output" == *"ERİŞİM LİSTESİ"* && "$output" == *"paket sizin adınıza"* ]] || false
  [ "$(yayin)" = "" ]
  [ "$(lab docker inspect -f '{{.Config.Image}} {{.State.Health.Status}}' kurulum-redisui)" = "redis/redisinsight:3.10.1 healthy" ]
  [ "$(lab docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' kurulum-redisui)" = kurulum ]
  run lab sh -c 'stat -c "%a %U" /srv/homelab/redisui/.env; stat -c "%a %u" /srv/homelab/redisui/data; grep -cE "^(RI_ENCRYPTION_KEY|RI_REDIS_PASSWORD)=.{32}$" /srv/homelab/redisui/.env; grep -ciE "PASSWORD|ENCRYPTION|ACCEPT_TERMS" /srv/homelab/redisui/compose.yml | head -n1; grep -c "^REDISUI_" /srv/homelab/.env'
  [ "${lines[0]}" = "600 root" ] && [ "${lines[1]}" = "700 1000" ] && [ "${lines[2]}" = 2 ]
  [ "${lines[3]}" = 0 ] && [ "${lines[4]}" = 0 ]
  [ "$(parolalar_esit)" = esit ]
  [ "$(lab docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' kurulum-redisui | grep -c '^RI_ACCEPT')" = 0 ]
}

@test "koşullar kullanıcı adına kabul edilmemiş: ayarlarda onay yok, onaydan önce bağlantı listesi boş" {
  run api /api/settings
  [ "$status" -eq 0 ]
  echo "# settings: $output" >&3
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); a=d.get("agreements") or {}; assert not a.get("eula"), a; assert d.get("acceptTermsAndConditionsOverwritten") is False, d' "$output"
  run api /api/databases
  echo "# databases: $status $output" >&3
  [[ "$output" != *"kurulum-redis"* ]] || false
}

@test "ic: dışarıdan ve sunucunun 127.0.0.1'inden erişilemez; ortak ağdan konteyner adıyla erişilir; bağlantı bilgisi Redis'e giriş yapar" {
  run disaridan
  [ "$status" -ne 0 ]
  run sunucudan
  [ "$status" -ne 0 ]
  run adla_erisim
  [[ "$output" == *'{"status":"up"}'* ]] || false
  [ "$(baglanti_dene)" = "+OK" ]
}

@test "ikinci redisui_kur ve önizleme: changed=0, konteyner yeniden yaratılmaz" {
  once=$(kimlik); k=$(anahtar_ozeti)
  krun redisui_kur -e kurulum_redisui_surum=3.10.1
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
  [ "$(anahtar degisen)" = 0 ]
  krun redisui_onizle -e kurulum_redisui_surum=3.10.1
  [ "$(anahtar degisen)" = 0 ]
  [ "$(kimlik)" = "$once" ]
  [ "$(anahtar_ozeti)" = "$k" ]
}

@test "redisui_durum: kurulu ve durmuş; NPM hedefi; genel özet redisui_kurulu, kurulu/portlar'a GİRMEZ" {
  ri_beklenen evet docker ic 3.10.1 ic "$HEDEF"
  krun kurulum_durum
  [ "$(anahtar redisui_kurulu)" = evet ]
  [ "$(anahtar kurulu) $(anahtar portlar)" = "docker:native+redis:docker yok" ]
  lab docker stop kurulum-redisui >/dev/null
  ri_beklenen durmus docker unknown 3.10.1 unknown "$HEDEF"
  krun redisui_kur -e kurulum_redisui_surum=3.10.1
  [ "$status" -eq 0 ]
  ri_beklenen evet docker ic 3.10.1 ic "$HEDEF"
}

@test "sunucu: 5540 doluysa durur; değilse yalnız 127.0.0.1'de yayınlanır; ic'e dönünce yayın kalkar" {
  lab systemd-run --quiet --unit=lab-dinle-5540 python3 -m http.server 5540
  sleep 2
  once=$(ozet)
  krun redisui_kur -e kurulum_redisui_surum=3.10.1 -e kurulum_redisui_erisim=sunucu
  lab systemctl stop lab-dinle-5540
  [ "$status" -ne 0 ]
  [[ "$output" == *"5540 portunu sunucuda başka bir süreç dinliyor"* ]] || false
  [ "$(ozet)" = "$once" ]
  krun redisui_onizle -e kurulum_redisui_surum=3.10.1 -e kurulum_redisui_erisim=sunucu
  [[ "$output" == *"DEĞİŞECEK redisui"* ]] || false
  [ "$(yayin)" = "" ]
  krun redisui_kur -e kurulum_redisui_surum=3.10.1 -e kurulum_redisui_erisim=sunucu
  [ "$status" -eq 0 ]
  [[ "$output" == *"ssh -L 5540:127.0.0.1:5540"* ]] || false
  [ "$(yayin)" = "5540/tcp -> 127.0.0.1:5540" ]
  sunucudan
  run disaridan
  [ "$status" -ne 0 ]
  ri_beklenen evet docker 5540 3.10.1 sunucu "$HEDEF"
  krun redisui_kur -e kurulum_redisui_surum=3.10.1
  [ "$(yayin)" = "" ]
}

@test "Redis parolası değişince önizleme gösterir ve yazmaz; redisui_kur kopyalar, yeniden yaratır; şifreleme anahtarı aynı" {
  k=$(anahtar_ozeti); once=$(kimlik)
  lab sh -c 'y=$(head -c 96 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32); sed -i "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=$y/" /srv/homelab/redis/.env && docker compose --progress quiet -p kurulum-redis -f /srv/homelab/redis/compose.yml up -d'
  [ "$(parolalar_esit)" = FARKLI ]
  d=$(ozet)
  krun redisui_onizle -e kurulum_redisui_surum=3.10.1
  [ "$status" -eq 0 ]
  [ "$(anahtar degisen)" != 0 ]
  [ "$(ozet)" = "$d" ]
  [ "$(parolalar_esit)" = FARKLI ]
  krun redisui_kur -e kurulum_redisui_surum=3.10.1
  [ "$status" -eq 0 ]
  [ "$(parolalar_esit)" = esit ]
  [ "$(kimlik)" != "$once" ]
  [ "$(anahtar_ozeti)" = "$k" ]
  sleep 5
  [ "$(baglanti_dene)" = "+OK" ]
  krun redisui_kur -e kurulum_redisui_surum=3.10.1
  [ "$(recap_changed)" = 0 ]
}

@test "redisui_kur sürümü sessizce değiştirmez; redisui_yukselt önce yedek alır; veri ve anahtar korunur" {
  lab sh -c 'echo iz > /srv/homelab/redisui/data/lab-iz'
  once=$(kimlik); k=$(anahtar_ozeti)
  krun redisui_kur
  [ "$status" -ne 0 ]
  [[ "$output" == *"redisui_yukselt"* ]] || false
  [ "$(kimlik)" = "$once" ]
  krun redisui_yukselt
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.redisui_yukselt yazilim=redisui mod=docker surum=3.10.2 "* ]] || false
  [ "$(lab docker inspect -f '{{.Config.Image}} {{.State.Health.Status}}' kurulum-redisui)" = "redis/redisinsight:3.10.2 healthy" ]
  run lab sh -c 'd=$(ls -d /srv/homelab/redisui/yedek/*/ | head -n1); stat -c %a "$d"; test -f "$d/data/lab-iz" && test -n "$(ls "$d/data" | grep -v lab-iz)" && cmp -s "$d/env" /srv/homelab/redisui/.env && grep -q 3.10.1 "$d/compose.yml" && echo yedek-tamam'
  [ "${lines[0]}" = 700 ] && [ "${lines[1]}" = yedek-tamam ]
  [ "$(lab cat /srv/homelab/redisui/data/lab-iz)" = iz ]
  [ "$(anahtar_ozeti)" = "$k" ]
  ri_beklenen evet docker ic 3.10.2 ic "$HEDEF"
  krun redisui_kur
  [ "$(recap_changed)" = 0 ]
  krun redisui_yukselt
  [ "$status" -ne 0 ]
}

@test "kaldir: konteyner gider, veri ve anahtar kalır, Redis'e dokunulmaz; yeniden kur aynı anahtarla açılır" {
  k=$(anahtar_ozeti); r=$(lab docker inspect -f '{{.Id}}' kurulum-redis)
  krun kaldir -e kurulum_yazilim=redisui
  [ "$status" -eq 0 ]
  run lab sh -c '! docker ps -a --format "{{.Names}}" | grep -qx kurulum-redisui && test -f /srv/homelab/redisui/data/lab-iz && test -f /srv/homelab/redisui/.env && echo kaldi'
  [ "$output" = kaldi ]
  [ "$(lab docker inspect -f '{{.Id}}' kurulum-redis)" = "$r" ]
  ri_beklenen hayir yok yok yok yok yok
  krun redisui_kur
  [ "$status" -eq 0 ]
  [[ "$(result)" == *" gizli=0" ]] || false
  [ "$(anahtar_ozeti)" = "$k" ]
  [ "$(lab cat /srv/homelab/redisui/data/lab-iz)" = iz ]
  [ "$(baglanti_dene)" = "+OK" ]
}

@test "PAROLA VE ANAHTAR SIZMIYOR (çıktı, ayrıntılı çıktı, fark, günlükler) ve TEMİZ ÇIKTI" {
  # parolanın YAZILDIĞI yol da ayrıntılı çıktıyla koşmalı: satır silinir, kur yeniden kopyalar
  lab sed -i '/^RI_REDIS_PASSWORD=/d' /srv/homelab/redisui/.env
  krun redisui_onizle -v
  [ "$(anahtar degisen)" != 0 ]
  krun redisui_kur -v --diff
  [ "$status" -eq 0 ]
  [ "$(anahtar degisen)" != 0 ]
  [ "$(parolalar_esit)" = esit ]
  krun redisui_durum -v
  pw=$(lab sh -c 'sed -n s/^REDIS_PASSWORD=//p /srv/homelab/redis/.env')
  key=$(lab sh -c 'sed -n s/^RI_ENCRYPTION_KEY=//p /srv/homelab/redisui/.env')
  [ "${#pw}" -ge 24 ] && [ "${#key}" -ge 24 ]
  for d in "$pw" "$key"; do
    run grep -cF -- "$d" "$BATS_FILE_TMPDIR/hepsi.log"
    [ "$output" = 0 ] || return 1
    run bash -c "docker exec kurulum-lab sh -c 'docker logs kurulum-redisui 2>&1; cat /srv/homelab/redisui/compose.yml; cat /srv/homelab/redisui/data/logs/* 2>/dev/null; true' | grep -cF -- '$d'"
    [ "$output" = 0 ] || return 1
  done
  run beklenmeyen_uyarilar "$BATS_FILE_TMPDIR/hepsi.log"
  echo "$output" >&3
  [ "$status" -eq 1 ]
}
