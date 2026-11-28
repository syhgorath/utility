#!/usr/bin/env bats
# LAB e2e: Nginx Proxy Manager (proxy_onizle, proxy_kur, proxy_yukselt, proxy_durum, kaldir), port çakışması, yönetim erişimi ve ortak ağdan konteyner
# adıyla erişim. NPM'ye giriş YAPILMAZ; yalnız oturumsuz durum yanıtı ("setup": hesap var mı) okunur. İmajlar internetten indirilir. SIRALI testler.
# Gerçek VM yerine GEÇMEZ. Ağda TLS'i araya giren yazılım varsa: LAB_CA_FILE=<kök sertifika.pem>
# DİKKAT: macOS bash 3.2 ile bats, testin ortasındaki başarısız [[ ]] ifadesini YOK SAYAR; bu yüzden her [[ ]] "|| false" ile biter.
# shellcheck disable=SC2016  # tek tırnak içindeki $ ifadeleri bilerek sunucuda genişler
load ortak

anahtar() { local v; v=$(result | tr ' ' '\n' | sed -n "s/^$1=//p"); echo "${v:--}"; }
# proxy_beklenen <kurulu> <mod> <port> <surum> <yonetim> <adres> <duvar>
proxy_beklenen() {
  krun proxy_durum
  [ "$status" -eq 0 ] || return 1
  [ "$(recap_changed)" = 0 ] || return 1
  local g
  g="SSHPOCKET_RESULT utility.proxy_durum ana_durum=$(anahtar ana_durum) proxy_kurulu=$1 proxy_mod=$2 proxy_port=$3 proxy_surum=$4 proxy_yonetim=$5 proxy_adres=$6 proxy_duvar=$7"
  [ "$(result)" = "$g" ] || { echo "beklenen: $g"; echo "gelen:    $(result)"; return 1; } >&2
}
# kapsayıcının yayınladığı adresler, sıralı tek satır
yayin() { lab docker port kurulum-proxy 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//'; }
kimlik() { lab docker inspect -f '{{.Id}} {{.State.StartedAt}}' kurulum-proxy; }
ozet() { lab sh -c 'sha256sum /srv/homelab/.kurulum /srv/homelab/.env 2>/dev/null; cat /srv/homelab/proxy/compose.yml 2>/dev/null | sha256sum; docker ps -a --format "{{.Names}} {{.Image}}" | sort'; }
# LAB sunucusunun DIŞINDAN (aynı Docker ağındaki ayrı konteyner) porta TCP bağlantısı
ulasilir() {
  local ip img
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' kurulum-lab)
  img=$(docker inspect -f '{{.Config.Image}}' kurulum-lab)
  docker run --rm --entrypoint timeout "$img" 5 bash -c "</dev/tcp/$ip/$1" 2>/dev/null
}
# NPM'nin oturumsuz durum yanıtındaki "setup" alanı: false = henüz hesap yok
kurulum_durumu() { lab curl -fsS http://127.0.0.1:81/api/ | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["status"], d["setup"])'; }

# LAB sunucusuna "genel" bir IPv4 adresi takar/çıkarır (yalnız konteynerin içinde; dışarıya trafik üretmez)
GENEL=11.22.33.44
genel_ekle() { lab ip addr add "$GENEL/32" dev eth0; }
genel_sil() { lab ip addr del "$GENEL/32" dev eth0; }
YAYIN_AGDAN="443/tcp -> 0.0.0.0:443 80/tcp -> 0.0.0.0:80 81/tcp -> 0.0.0.0:81"
YAYIN_SUNUCU="443/tcp -> 0.0.0.0:443 80/tcp -> 0.0.0.0:80 81/tcp -> 127.0.0.1:81"

setup_file() {
  : > "$BATS_FILE_TMPDIR/hepsi.log"
  "$BATS_TEST_DIRNAME/lab/up.sh" >&3
  docker exec kurulum-lab sh -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y -q curl >/dev/null 2>&1'
}

@test "temiz sunucu: proxy yok; genel özet proxy_kurulu=hayir" {
  proxy_beklenen hayir yok yok yok yok yok gerekmez
  krun kurulum_durum
  [ "$(anahtar proxy_kurulu)" = hayir ]
}

@test "Docker yokken proxy_onizle ve proxy_kur açık mesajla durur, hiçbir şey yazmaz" {
  for e in proxy_onizle proxy_kur; do
    krun "$e"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"Docker"* && "$output" == *"Docker taban kurulumunu"* ]] || return 1
  done
  run lab sh -c 'test ! -e /srv/homelab && test ! -e /etc/kurulum && ! command -v docker >/dev/null && echo temiz'
  [ "$output" = temiz ]
}

@test "port çakışması: 80'i dinleyen native nginx varken proxy_kur hiçbir şeyi değiştirmeden durur" {
  krun docker_kur
  [ "$status" -eq 0 ]
  krun nginx_kur -e kurulum_nginx_mod=native -e kurulum_nginx_port=80 -e kurulum_nginx_erisim=agdan
  [ "$status" -eq 0 ]
  once=$(ozet)
  for e in proxy_onizle proxy_kur; do
    krun "$e"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"80, 443 ve 81 portlarını ister"* && "$output" == *"80 (nginx uygulamasına verilmiş)"* ]] || return 1
  done
  [ "$(ozet)" = "$once" ]
  run lab sh -c 'test ! -e /srv/homelab/proxy && echo temiz'
  [ "$output" = temiz ]
  krun kaldir -e kurulum_yazilim=nginx
  [ "$status" -eq 0 ]
}

@test "port çakışması: yönetilmeyen süreç 81'i ya da 443'ü dinliyorsa durur" {
  for p in 81 443; do
    lab systemd-run --quiet --unit="lab-dinle-$p" python3 -m http.server "$p"
    sleep 2
    krun proxy_kur
    lab systemctl stop "lab-dinle-$p"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"$p (sunucuda başka bir süreç dinliyor)"* ]] || return 1
  done
  run lab sh -c 'test ! -e /srv/homelab/proxy && ! docker ps -a --format "{{.Names}}" | grep -q kurulum-proxy && echo temiz'
  [ "$output" = temiz ]
}

@test "geçersiz yönetim değeri ve sürüm reddedilir" {
  krun proxy_kur -e kurulum_proxy_yonetim=ic
  [ "$status" -ne 0 ]
  krun proxy_kur -e kurulum_proxy_surum=2.16.0
  [ "$status" -ne 0 ]
  run lab sh -c 'test ! -e /srv/homelab/proxy && echo temiz'
  [ "$output" = temiz ]
}

@test "proxy_onizle hiçbir şey yazmaz; proxy_kur (otomatik: genel adres yok -> agdan, 2.17.0) kurar ve ilk giriş uyarısını yazar" {
  krun proxy_onizle -e kurulum_proxy_surum=2.17.0 -e kurulum_yazilim=redis -e kurulum_mod=native
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.proxy_onizle yazilim=proxy mod=docker surum=2.17.0 port=80 "* ]] || false
  run lab sh -c 'test ! -e /srv/homelab/proxy && echo temiz'
  [ "$output" = temiz ]
  krun proxy_kur -e kurulum_proxy_surum=2.17.0 -e kurulum_yazilim=redis -e kurulum_mod=native
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.proxy_kur yazilim=proxy mod=docker surum=2.17.0 port=80 "* ]] || false
  [[ "$output" == *"İLK GİRİŞ"* && "$output" == *"TÜM ağ arayüzlerinde"* && "$output" == *"ufw kurallarına TAKILMAZ"* ]] || false
  [[ "$output" == *"otomatik -> agdan (sunucuda genel IPv4 adresi görünmüyor"* && "$output" != *"İNTERNETE AÇIK"* ]] || false
  [[ "$output" != *"kurulum_proxy_erisim"* ]] || false
  [ "$(yayin)" = "443/tcp -> 0.0.0.0:443 80/tcp -> 0.0.0.0:80 81/tcp -> 0.0.0.0:81" ]
  [ "$(lab docker inspect -f '{{.Config.Image}} {{.State.Health.Status}}' kurulum-proxy)" = "jc21/nginx-proxy-manager:2.17.0 healthy" ]
  [ "$(lab docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' kurulum-proxy)" = kurulum ]
  run lab sh -c 'stat -c %a /srv/homelab/proxy; test -d /srv/homelab/proxy/data && test -d /srv/homelab/proxy/letsencrypt && ! test -e /srv/homelab/proxy/.env && ! grep -q "^PROXY_" /srv/homelab/.env && ! grep -qi "INITIAL_ADMIN\|password" /srv/homelab/proxy/compose.yml && echo tamam'
  [ "${lines[0]}" = 750 ] && [ "${lines[1]}" = tamam ]
}

@test "ilk açılışta hazır hesap yok (setup=false); dışarıdan 80, 443 ve 81'e erişilir" {
  [ "$(kurulum_durumu)" = "OK False" ]
  ulasilir 80
  ulasilir 81
  ulasilir 443
}

@test "proxy_durum kurulu: yönetim adresi sunucuya bağlanılan ad; genel özet proxy_kurulu=evet, kurulu/portlar'a GİRMEZ" {
  proxy_beklenen evet docker 80 2.17.0 agdan 127.0.0.1:81 atlanir
  # adres envanterdeki bağlantı adından gelir (LAB'a "localhost" adıyla bağlanılır; yalnız bu koşuda sunucu anahtarı denetimi kapalı)
  krun proxy_durum -e ansible_host=localhost -e '{"ansible_ssh_common_args":"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o LogLevel=ERROR"}'
  [ "$(anahtar proxy_adres)" = localhost:81 ]
  krun kurulum_durum
  [ "$(anahtar proxy_kurulu)" = evet ]
  [ "$(anahtar kurulu) $(anahtar portlar)" = "docker:native yok" ]
}

@test "ikinci proxy_kur ve önizleme: changed=0, konteyner yeniden yaratılmaz" {
  once=$(kimlik)
  krun proxy_kur -e kurulum_proxy_surum=2.17.0
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
  [ "$(anahtar degisen)" = 0 ]
  krun proxy_onizle -e kurulum_proxy_surum=2.17.0
  [ "$(anahtar degisen)" = 0 ]
  [ "$(kimlik)" = "$once" ]
}

@test "ortak ağdan konteyner adıyla erişim: iç ağdaki nginx'e proxy konteynerinden ulaşılır; dışarıya port yayınlamaz" {
  krun nginx_kur -e kurulum_nginx_mod=docker -e kurulum_nginx_erisim=ic
  [ "$status" -eq 0 ]
  [ "$(lab docker port kurulum-nginx)" = "" ]
  run lab docker exec kurulum-proxy curl -s -o /dev/null -w '%{http_code}' http://kurulum-nginx:80/
  [ "$output" = 200 ]
}

@test "yönetim erişimi sunucu: 81 yalnız 127.0.0.1; 80/443 açık kalır; DEĞİŞECEK uyarısı; veri durur" {
  lab sh -c 'echo iz > /srv/homelab/proxy/data/lab-iz'
  krun proxy_onizle -e kurulum_proxy_surum=2.17.0 -e kurulum_proxy_yonetim=sunucu
  [[ "$output" == *"DEĞİŞECEK proxy yönetim erişimi agdan -> sunucu"* ]] || false
  [ "$(anahtar degisen)" != 0 ]
  [ "$(yayin)" = "443/tcp -> 0.0.0.0:443 80/tcp -> 0.0.0.0:80 81/tcp -> 0.0.0.0:81" ]
  krun proxy_kur -e kurulum_proxy_surum=2.17.0 -e kurulum_proxy_yonetim=sunucu
  [ "$status" -eq 0 ]
  [[ "$output" == *"ssh -L 8181:127.0.0.1:81"* ]] || false
  [ "$(yayin)" = "443/tcp -> 0.0.0.0:443 80/tcp -> 0.0.0.0:80 81/tcp -> 127.0.0.1:81" ]
  run ulasilir 81
  [ "$status" -ne 0 ]
  ulasilir 80
  proxy_beklenen evet docker 80 2.17.0 sunucu 127.0.0.1:81 atlanir
  [ "$(lab cat /srv/homelab/proxy/data/lab-iz)" = iz ]
  krun proxy_kur -e kurulum_proxy_surum=2.17.0
  [ "$(yayin)" = "443/tcp -> 0.0.0.0:443 80/tcp -> 0.0.0.0:80 81/tcp -> 0.0.0.0:81" ]
}

@test "otomatik: genel IPv4 eklenince önizleme DEĞİŞECEK der ve yazmaz; kur 81'i yalnız sunucuya alır; ikinci kur changed=0" {
  genel_ekle
  once=$(kimlik)
  krun proxy_onizle -e kurulum_proxy_surum=2.17.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"otomatik -> sunucu (sunucuda genel IPv4 adresi var: $GENEL)"* ]] || false
  [[ "$output" == *"DEĞİŞECEK proxy yönetim erişimi agdan -> sunucu"* ]] || false
  [ "$(anahtar degisen)" != 0 ]
  [ "$(kimlik)" = "$once" ]
  [ "$(yayin)" = "$YAYIN_AGDAN" ]
  proxy_beklenen evet docker 80 2.17.0 agdan 127.0.0.1:81 atlanir   # okuma gerçek yayını bildirir, seçimi değil
  krun proxy_kur -e kurulum_proxy_surum=2.17.0
  [ "$status" -eq 0 ]
  [ "$(yayin)" = "$YAYIN_SUNUCU" ]
  run ulasilir 81
  [ "$status" -ne 0 ]
  proxy_beklenen evet docker 80 2.17.0 sunucu 127.0.0.1:81 atlanir
  krun proxy_kur -e kurulum_proxy_surum=2.17.0
  [ "$(recap_changed)" = 0 ]
}

@test "elle agdan üstündür: genel adres varken ağa açılır ve açık uyarı çıkar (önizlemede de); adres gidince otomatik agdan'a döner" {
  for e in proxy_onizle proxy_kur; do
    krun "$e" -e kurulum_proxy_surum=2.17.0 -e kurulum_proxy_yonetim=agdan
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"agdan (elle seçildi)"* ]] || return 1
    [[ "$output" == *"elle 'agdan' seçildi ve sunucuda genel IPv4 adresi var ($GENEL): 81 İNTERNETE AÇIK"* ]] || return 1
  done
  [ "$(yayin)" = "$YAYIN_AGDAN" ]
  ulasilir 81
  krun proxy_kur -e kurulum_proxy_surum=2.17.0
  [ "$(yayin)" = "$YAYIN_SUNUCU" ]
  genel_sil
  krun proxy_onizle -e kurulum_proxy_surum=2.17.0
  [[ "$output" == *"DEĞİŞECEK proxy yönetim erişimi sunucu -> agdan"* ]] || false
  [ "$(yayin)" = "$YAYIN_SUNUCU" ]
  krun proxy_kur -e kurulum_proxy_surum=2.17.0
  [ "$(yayin)" = "$YAYIN_AGDAN" ]
  [[ "$output" != *"İNTERNETE AÇIK"* ]] || false
}

@test "yalnız genel IPv6 adresi 81'i kapatmaz (agdan kalır); 81 IPv6'da hiç dinlenmez" {
  lab sysctl -qw net.ipv6.conf.all.disable_ipv6=0 net.ipv6.conf.eth0.disable_ipv6=0 net.ipv6.conf.lo.disable_ipv6=0
  lab ip -6 addr add 2001:4860:4860::1234/128 dev eth0
  sleep 2
  krun proxy_onizle -e kurulum_proxy_surum=2.17.0
  [[ "$output" == *"otomatik -> agdan"* ]] || false
  [ "$(anahtar degisen)" = 0 ]
  run lab sh -c "ss -ltnH 'sport = :81' | awk '{print \$4}' | tr '\n' ' '"
  [ "$output" = "0.0.0.0:81 " ]
  run lab sh -c 'curl -s -o /dev/null -m 5 http://127.0.0.1:81/ && echo v4-var; curl -g -s -o /dev/null -m 5 "http://[::1]:81/" || echo v6-lo-yok; curl -g -s -o /dev/null -m 5 "http://[2001:4860:4860::1234]:81/" || echo v6-genel-yok'
  [ "$output" = "$(printf 'v4-var\nv6-lo-yok\nv6-genel-yok')" ]
  lab ip -6 addr del 2001:4860:4860::1234/128 dev eth0
}

@test "adres okunamazsa güvenli yön: sunucu" {
  # asıl dosya taşınır: /usr/sbin/ip çoğu sistemde ona sembolik bağdır, yalnız bağı taşımak komutu bozmaz
  yol=$(lab sh -c 'readlink -f "$(command -v ip)"')
  lab mv "$yol" "$yol.lab"
  run lab sh -c 'ip -4 -o addr show'
  [ "$status" -ne 0 ] || { lab mv "$yol.lab" "$yol"; false; }
  krun proxy_kur -e kurulum_proxy_surum=2.17.0
  lab mv "$yol.lab" "$yol"
  [ "$status" -eq 0 ]
  [[ "$output" == *"otomatik -> sunucu (sunucunun adresleri okunamadı (ip komutu yok); güvenli yön seçildi)"* ]] || false
  [[ "$output" == *"DEĞİŞECEK proxy yönetim erişimi agdan -> sunucu"* ]] || false
  [ "$(yayin)" = "$YAYIN_SUNUCU" ]
  krun proxy_kur -e kurulum_proxy_surum=2.17.0
  [ "$(yayin)" = "$YAYIN_AGDAN" ]
}

@test "kurulu proxy'nin portları ayrılmıştır: durmuşken bile başka uygulama 80 ve 443'ü alamaz" {
  lab docker stop kurulum-proxy >/dev/null
  proxy_beklenen durmus docker unknown 2.17.0 unknown unknown unknown
  once=$(ozet)
  for p in 80 443 81; do
    krun redis_kur -e kurulum_redis_mod=docker -e kurulum_redis_erisim=sunucu -e "kurulum_redis_port=$p"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"$p portu proxy uygulamasına verilmiş"* ]] || return 1
  done
  [ "$(ozet)" = "$once" ]
  # durmuş proxy'nin portunu başka süreç almışsa kur reddeder
  lab systemd-run --quiet --unit=lab-dinle-80 python3 -m http.server 80
  sleep 2
  krun proxy_kur -e kurulum_proxy_surum=2.17.0
  lab systemctl stop lab-dinle-80
  [ "$status" -ne 0 ]
  [[ "$output" == *"80 (sunucuda başka bir süreç dinliyor)"* ]] || false
  krun proxy_kur -e kurulum_proxy_surum=2.17.0
  [ "$status" -eq 0 ]
  [ "$(lab docker inspect -f '{{.State.Running}}' kurulum-proxy)" = true ]
}

@test "proxy_kur sürümü sessizce değiştirmez; proxy_yukselt önce yedek alır, veri ve hesap durumu korunur" {
  once=$(kimlik)
  krun proxy_kur
  [ "$status" -ne 0 ]
  [[ "$output" == *"proxy_yukselt"* ]] || false
  [ "$(kimlik)" = "$once" ]
  krun proxy_yukselt
  [ "$status" -eq 0 ]
  [[ "$(result)" == "SSHPOCKET_RESULT utility.proxy_yukselt yazilim=proxy mod=docker surum=2.17.1 "* ]] || false
  [ "$(lab docker inspect -f '{{.Config.Image}} {{.State.Health.Status}}' kurulum-proxy)" = "jc21/nginx-proxy-manager:2.17.1 healthy" ]
  run lab sh -c 'd=$(ls -d /srv/homelab/proxy/yedek/*/ | head -n1); stat -c %a "$d"; test -f "$d/data/lab-iz" && test -s "$d/data/database.sqlite" && test -d "$d/letsencrypt" && grep -q 2.17.0 "$d/compose.yml" && echo yedek-tamam'
  [ "${lines[0]}" = 700 ] && [ "${lines[1]}" = yedek-tamam ]
  [ "$(lab cat /srv/homelab/proxy/data/lab-iz)" = iz ]
  [ "$(kurulum_durumu)" = "OK False" ]
  proxy_beklenen evet docker 80 2.17.1 agdan 127.0.0.1:81 atlanir
  krun proxy_kur
  [ "$(recap_changed)" = 0 ]
  krun proxy_yukselt
  [ "$status" -ne 0 ]
}

@test "kaldir: konteyner gider, veri ve sertifikalar kalır; yeniden kur aynı veriyle açılır" {
  krun kaldir -e kurulum_yazilim=proxy
  [ "$status" -eq 0 ]
  run lab sh -c '! docker ps -a --format "{{.Names}}" | grep -q kurulum-proxy && test -f /srv/homelab/proxy/data/lab-iz && test -s /srv/homelab/proxy/data/database.sqlite && echo kaldi'
  [ "$output" = kaldi ]
  proxy_beklenen hayir yok yok yok yok yok gerekmez
  krun proxy_kur
  [ "$status" -eq 0 ]
  [ "$(lab cat /srv/homelab/proxy/data/lab-iz)" = iz ]
}

@test "genel adresli sunucuda YENİ kurulum 81'i yalnız sunucuda açar" {
  krun kaldir -e kurulum_yazilim=proxy
  [ "$status" -eq 0 ]
  genel_ekle
  krun proxy_kur
  genel_sil
  [ "$status" -eq 0 ]
  [[ "$output" == *"otomatik -> sunucu"* && "$output" == *"ssh -L 8181:127.0.0.1:81"* && "$output" != *"DEĞİŞECEK proxy"* ]] || false
  [ "$(yayin)" = "$YAYIN_SUNUCU" ]
  run ulasilir 81
  [ "$status" -ne 0 ]
  proxy_beklenen evet docker 80 2.17.1 sunucu 127.0.0.1:81 atlanir
}

@test "ÇIKTIDA PAROLA YOK (günlük dahil) ve TEMİZ ÇIKTI" {
  krun proxy_durum -v
  run lab sh -c 'docker logs kurulum-proxy 2>&1 | grep -ciE "with password|changeme"'
  [ "$output" = 0 ]
  run grep -ciE 'INITIAL_ADMIN|changeme|with password' "$BATS_FILE_TMPDIR/hepsi.log"
  [ "$output" = 0 ]
  run beklenmeyen_uyarilar "$BATS_FILE_TMPDIR/hepsi.log"
  echo "$output" >&3
  [ "$status" -eq 1 ]
}
