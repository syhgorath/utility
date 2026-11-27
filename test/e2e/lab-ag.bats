#!/usr/bin/env bats
# LAB e2e: uygulama başına ağ erişimi (kurulum_<yz>_erisim: otomatik|ic|sunucu|agdan) ve iç ağ adı (kurulum_docker_ag).
# SUNUCUDAKİ gerçek durum (docker port, ss, .env, işaret) denetlenir. SIRALI testler. Gerçek VM yerine GEÇMEZ.
# Ağda TLS'i araya giren yazılım varsa: LAB_CA_FILE=<kök sertifika.pem>
# DİKKAT: macOS bash 3.2 ile bats, testin ortasındaki başarısız [[ ]] ifadesini YOK SAYAR; bu yüzden her [[ ]] "|| false" ile biter.
# shellcheck disable=SC2016  # tek tırnak içindeki $ ifadeleri bilerek sunucuda genişler
load ortak

NG=(-e kurulum_yazilim=nginx -e kurulum_mod=docker)
MA=(-e kurulum_yazilim=mariadb -e kurulum_mod=docker)
RE=(-e kurulum_yazilim=redis -e kurulum_mod=docker)

yayin() { lab docker port "kurulum-$1" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
dinleyen() { lab sh -c "ss -ltnH | awk '{print \$4}' | grep -E ':$1\$' | sort | tr '\n' ' ' | sed 's/ \$//'"; }
# isaret <yazılım> <alan>   (alan yoksa "-")
isaret() { lab python3 -c "import json; print(json.load(open('/srv/homelab/.kurulum'))['yazilimlar']['$1'].get('$2','-'))"; }
ust_isaret() { lab python3 -c "import json; print(json.load(open('/srv/homelab/.kurulum')).get('$1','-'))"; }
env_satiri() { lab sh -c "grep '^$1=' /srv/homelab/.env || true"; }
ag_adi() { lab docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "kurulum-$1"; }
# konteynere, dosyalarına ve kayda dokunulmadığının kanıtı
ozet() { lab sh -c "docker inspect -f '{{.Id}} {{.State.StartedAt}} {{.State.Running}}' kurulum-$1; sha256sum /srv/homelab/$1/compose.yml /srv/homelab/.env /srv/homelab/.kurulum"; }

setup_file() {
  : > "$BATS_FILE_TMPDIR/hepsi.log"
  "$BATS_TEST_DIRNAME/lab/up.sh" >&3
}

@test "hazırlık: docker taban" {
  krun kur -e kurulum_yazilim=docker
  [ "$status" -eq 0 ]
}

@test "yeni mariadb docker (otomatik) yalnız iç ağ: port yayınlanmaz, HOST_PORT yazılmaz, ağda adıyla erişilir; ikinci kur changed=0" {
  krun kur "${MA[@]}"
  [ "$status" -eq 0 ]
  [[ "$(result)" == *" mod=docker surum=11.4.13 port=0 "* ]] || false
  [ "$(yayin mariadb)" = "" ]
  [ "$(dinleyen 3306)" = "" ]
  [ "$(isaret mariadb erisim)" = ic ]
  [ "$(isaret mariadb port)" = 0 ]
  [ "$(env_satiri MARIADB_HOST)" = "MARIADB_HOST=mariadb" ]
  [ "$(env_satiri MARIADB_PORT)" = "MARIADB_PORT=3306" ]
  [ "$(env_satiri MARIADB_HOST_PORT)" = "" ]
  run lab docker run --rm --network kurulum mariadb:11.4.13 bash -c 'exec 3<>/dev/tcp/mariadb/3306 && echo erisildi'
  [ "$output" = erisildi ]
  krun kur "${MA[@]}"
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
}

@test "yeni redis docker (otomatik) yalnız iç ağ; yeni nginx docker (otomatik) bu sunucudan" {
  krun kur "${RE[@]}" -e kurulum_redis_surum=7.2.17
  [ "$status" -eq 0 ]
  [ "$(yayin redis)" = "" ]
  [ "$(isaret redis erisim)" = ic ]
  krun kur "${NG[@]}"
  [ "$status" -eq 0 ]
  [ "$(yayin nginx)" = "80/tcp -> 127.0.0.1:8080" ]
  [ "$(isaret nginx erisim)" = sunucu ]
  [ "$(env_satiri NGINX_HOST_PORT)" = "NGINX_HOST_PORT=8080" ]
  krun kurulum_durum
  [[ "$(result)" == *" portlar=nginx:8080 nginx_kurulu=evet "* ]] || false
}

@test "iç ağda port denetimi yapılmaz: başka uygulamanın portu verilse de kur geçer" {
  krun kur "${MA[@]}" -e kurulum_mariadb_port=8080
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
}

@test "iç ağ -> bu sunucudan: dolu port reddedilir (dokunulmaz); boş portta yayınlanır ve HOST_PORT yazılır" {
  docker exec -d kurulum-lab python3 -m http.server 3399 --bind 127.0.0.1
  sleep 1
  once=$(ozet mariadb)
  krun kur "${MA[@]}" -e kurulum_mariadb_erisim=sunucu -e kurulum_mariadb_port=3399
  [ "$status" -ne 0 ]
  [[ "$output" == *"3399 portunu sunucuda başka bir süreç dinliyor"* ]] || false
  [ "$(ozet mariadb)" = "$once" ]
  krun kur "${MA[@]}" -e kurulum_mariadb_erisim=sunucu
  [ "$status" -eq 0 ]
  [ "$(yayin mariadb)" = "3306/tcp -> 127.0.0.1:3306" ]
  [ "$(isaret mariadb erisim)" = sunucu ]
  [ "$(env_satiri MARIADB_HOST_PORT)" = "MARIADB_HOST_PORT=3306" ]
  krun kur "${MA[@]}" -e kurulum_mariadb_erisim=sunucu
  [ "$(recap_changed)" = 0 ]
}

@test "kurulu uygulamada otomatik davranışı korur: yayınlı kalır" {
  once=$(ozet mariadb)
  krun kur "${MA[@]}"
  [ "$status" -eq 0 ]
  [ "$(recap_changed)" = 0 ]
  [ "$(ozet mariadb)" = "$once" ]
}

@test "kurulu uygulama açıkça iç ağa alınır: uyarılır, yayın kalkar; sonra otomatik iç ağda tutar" {
  krun kurulum_onizle "${MA[@]}" -e kurulum_mariadb_erisim=ic
  [ "$status" -eq 0 ]
  [[ "$output" == *"iç ağa alınınca"* ]] || false
  [ "$(yayin mariadb)" = "3306/tcp -> 127.0.0.1:3306" ]
  krun kur "${MA[@]}" -e kurulum_mariadb_erisim=ic
  [ "$status" -eq 0 ]
  [ "$(yayin mariadb)" = "" ]
  [ "$(env_satiri MARIADB_HOST_PORT)" = "" ]
  krun kur "${MA[@]}"
  [ "$(recap_changed)" = 0 ]
  [ "$(isaret mariadb erisim)" = ic ]
}

@test "kurulum_dis_erisim=true (otomatik) ağdan yayınlar; docker uyarısı ufw'nin atlandığını söyler, ufw kuralı ÖNERMEZ" {
  krun kur "${NG[@]}" -e kurulum_dis_erisim=true
  [ "$status" -eq 0 ]
  [ "$(yayin nginx)" = "80/tcp -> 0.0.0.0:8080" ]
  [ "$(isaret nginx erisim)" = agdan ]
  [[ "$output" == *"ufw kurallarına TAKILMAZ"* ]] || false
  [[ "$output" != *"hardening_ufw_extra_allow_host"* ]] || false
}

@test "uygulama başına seçim genel ayarı ezer: dis_erisim=true iken nginx 'sunucu'" {
  krun kur "${NG[@]}" -e kurulum_dis_erisim=true -e kurulum_nginx_erisim=sunucu
  [ "$status" -eq 0 ]
  [ "$(yayin nginx)" = "80/tcp -> 127.0.0.1:8080" ]
  krun kur "${NG[@]}" -e kurulum_nginx_erisim=agdan
  [ "$status" -eq 0 ]
  [ "$(yayin nginx)" = "80/tcp -> 0.0.0.0:8080" ]
  krun kur "${NG[@]}"
  [ "$(yayin nginx)" = "80/tcp -> 127.0.0.1:8080" ]
}

@test "yukselt iç ağda: erişim korunur, veri durur" {
  lab sh -c 'docker exec kurulum-redis sh -c "redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning SET k v"'
  krun yukselt "${RE[@]}" -e kurulum_redis_surum=7.4.12
  [ "$status" -eq 0 ]
  [[ "$(result)" == *" surum=7.4.12 port=0 "* ]] || false
  [ "$(yayin redis)" = "" ]
  run lab sh -c 'docker exec kurulum-redis sh -c "redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning GET k"'
  [ "$output" = v ]
}

@test "eski kurulum uyumu: işarette erisim/docker_ag yokken kur konteynere dokunmaz, yayın aynı kalır" {
  krun kur "${MA[@]}" -e kurulum_mariadb_erisim=sunucu
  [ "$status" -eq 0 ]
  lab python3 -c "import json; p='/srv/homelab/.kurulum'; d=json.load(open(p)); d.pop('docker_ag',None); [v.pop('erisim',None) for v in d['yazilimlar'].values()]; open(p,'w').write(json.dumps(d,indent=2,sort_keys=True)+chr(10))"
  [ "$(isaret mariadb erisim)" = "-" ]
  once=$(lab sh -c "docker inspect -f '{{.Id}} {{.State.StartedAt}}' kurulum-mariadb; sha256sum /srv/homelab/mariadb/compose.yml /srv/homelab/.env")
  krun kur "${MA[@]}"
  [ "$status" -eq 0 ]
  [ "$(lab sh -c "docker inspect -f '{{.Id}} {{.State.StartedAt}}' kurulum-mariadb; sha256sum /srv/homelab/mariadb/compose.yml /srv/homelab/.env")" = "$once" ]
  [ "$(yayin mariadb)" = "3306/tcp -> 127.0.0.1:3306" ]
  [ "$(isaret mariadb erisim)" = sunucu ]
  [ "$(ust_isaret docker_ag)" = kurulum ]
  krun kur "${MA[@]}"
  [ "$(recap_changed)" = 0 ]
}

@test "geçersiz erişim değeri ve geçersiz ağ adları reddedilir" {
  once=$(ozet nginx)
  krun kur "${NG[@]}" -e kurulum_nginx_erisim=herkes
  [ "$status" -ne 0 ]
  for ad in bridge host none default "a b" "-x" 'a;b'; do
    krun kurulum_onizle "${NG[@]}" -e "{\"kurulum_docker_ag\":\"$ad\"}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"kurulum_docker_ag"* ]] || false
  done
  [ "$(ozet nginx)" = "$once" ]
}

@test "docker uygulaması kuruluyken ağ adı değişimi reddedilir; hiçbir şey değişmez" {
  once=$(ozet nginx)
  for eylem in kurulum_onizle kur yukselt; do
    surum=1.30.6
    if [ "$eylem" = yukselt ]; then surum=1.31.8; fi     # kur sürüm değiştirmez; o ret ağ denetiminden önce gelir
    krun "$eylem" "${NG[@]}" -e kurulum_docker_ag=labnet -e kurulum_nginx_surum=$surum
    [ "$status" -ne 0 ]
    [[ "$output" == *"ağ adı değiştirilemez"* ]] || false
  done
  [ "$(ozet nginx)" = "$once" ]
  run lab docker network inspect labnet
  [ "$status" -ne 0 ]
}

@test "kaldir ağ adından etkilenmez; kayıtlı ağ adı korunur" {
  for yz in nginx mariadb; do
    krun kaldir -e kurulum_yazilim=$yz -e kurulum_mod=docker -e kurulum_docker_ag=labnet
    [ "$status" -eq 0 ]
  done
  [ "$(ust_isaret docker_ag)" = kurulum ]
  [ "$(env_satiri KURULUM_DOCKER_AG)" = "KURULUM_DOCKER_AG=kurulum" ]
  krun kaldir "${RE[@]}" -e kurulum_redis_surum=7.4.12
  [ "$status" -eq 0 ]
}

@test "bridge olmayan mevcut ağ adı reddedilir" {
  lab docker network create -d macvlan -o parent=eth0 macnet
  krun kur "${NG[@]}" -e kurulum_docker_ag=macnet
  [ "$status" -ne 0 ]
  [[ "$output" == *"bridge"* ]] || false
  run lab sh -c 'docker ps -a --format "{{.Names}}" | grep -c kurulum-nginx || true'
  [ "$output" = 0 ]
}

@test "docker uygulaması yokken yeni ağ adı kabul edilir: ağ, .env ve işaret güncellenir; ikinci kur changed=0" {
  krun kur "${NG[@]}" -e kurulum_docker_ag=labnet
  [ "$status" -eq 0 ]
  [ "$(ag_adi nginx)" = labnet ]
  [ "$(env_satiri KURULUM_DOCKER_AG)" = "KURULUM_DOCKER_AG=labnet" ]
  [ "$(ust_isaret docker_ag)" = labnet ]
  krun kur "${NG[@]}" -e kurulum_docker_ag=labnet
  [ "$(recap_changed)" = 0 ]
}

@test "native: 'ic' açıkça istenirse (önizleme dahil) hiçbir şey değişmeden reddedilir" {
  once=$(lab sha256sum /srv/homelab/.env /srv/homelab/.kurulum)
  for eylem in kurulum_onizle kur; do
    krun "$eylem" -e kurulum_yazilim=mariadb -e kurulum_mod=native -e kurulum_mariadb_erisim=ic
    [ "$status" -ne 0 ]
    [[ "$output" == *"yalnız docker modunda"* ]] || false
  done
  [ "$(lab sha256sum /srv/homelab/.env /srv/homelab/.kurulum)" = "$once" ]
  run lab sh -c '! dpkg -s mariadb-server >/dev/null 2>&1 && echo temiz'
  [ "$output" = temiz ]
}

@test "native (otomatik) bu sunucudan; kayıtlı ağ adı değişmez; ağdan seçilince ufw önerisi gösterilir" {
  krun kur -e kurulum_yazilim=mariadb -e kurulum_mod=native
  [ "$status" -eq 0 ]
  [ "$(dinleyen 3306)" = "127.0.0.1:3306" ]
  [ "$(isaret mariadb erisim)" = sunucu ]
  [ "$(ust_isaret docker_ag)" = labnet ]
  [ "$(env_satiri KURULUM_DOCKER_AG)" = "KURULUM_DOCKER_AG=labnet" ]
  krun kur -e kurulum_yazilim=mariadb -e kurulum_mod=native -e kurulum_mariadb_erisim=agdan
  [ "$status" -eq 0 ]
  [ "$(dinleyen 3306)" = "0.0.0.0:3306" ]
  [ "$(isaret mariadb erisim)" = agdan ]
  [[ "$output" == *"hardening_ufw_extra_allow_host"* ]] || false
  [[ "$output" != *"ufw kurallarına TAKILMAZ"* ]] || false
  krun kaldir -e kurulum_yazilim=mariadb -e kurulum_mod=native -e kurulum_mariadb_erisim=ic
  [ "$status" -eq 0 ]
}

@test "PAROLA SIZMIYOR ve TEMİZ ÇIKTI" {
  pw=$(lab sh -c "grep '^[A-Z_]*PASSWORD=' /srv/homelab/redis/.env | cut -d= -f2-")
  [ "${#pw}" -ge 24 ]
  run grep -cF -- "$pw" "$BATS_FILE_TMPDIR/hepsi.log"
  [ "$output" = 0 ]
  run beklenmeyen_uyarilar "$BATS_FILE_TMPDIR/hepsi.log"
  echo "$output" >&3
  [ "$status" -eq 1 ]
}
