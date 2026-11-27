#!/usr/bin/env bats
# LAB e2e: (V04) depo/paket indeksi bayat ya da BOŞ olsa da `kur` kendini toparlar; (V05) sunucu saati sapmışsa net UYARI çıkar.
# Gerçek VM bulguları: Docker deposu eklendi ama `update` saat sapmasıyla düştü; yeniden çalıştırmada indeks güncellemesi atlandı ve
# "No package matching 'docker-ce'" ile düştü. SIRALI testler. Saat sapması sunucu saatini DEĞİŞTİRMEZ: yalnızca python süreci libfaketime ile geri alınır.
load ortak

setup_file() {
  : > "$BATS_FILE_TMPDIR/hepsi.log"
  "$BATS_TEST_DIRNAME/lab/up.sh" >&3
  docker exec kurulum-lab sh -c 'apt-get install -y -qq libfaketime >/dev/null 2>&1
    lib=$(find /usr/lib -name libfaketime.so.1 | head -1)
    printf "#!/bin/sh\nFAKETIME=\"${FAKETIME_FARK:--13d}\" LD_PRELOAD=%s exec python3 \"\$@\"\n" "$lib" > /usr/local/bin/py-faketime
    chmod 755 /usr/local/bin/py-faketime'
}

# apt dizinini "yakın zamanda güncellendi ama boş" yap (cache_valid_time bunu yakalayamaz)
indeks_boz() { lab sh -c 'rm -rf /var/lib/apt/lists/* && mkdir -p /var/lib/apt/lists/partial /var/lib/apt/periodic && touch /var/lib/apt/periodic/update-success-stamp'; }

@test "V05: normal koşuda saat uyarısı yok" {
  krun kurulum_durum
  [ "$status" -eq 0 ]
  [[ "$output" != *"sunucu saati kontrol makinesinden"* ]]
}

@test "V05: sunucu saati 13 gün geride -> net UYARI (GERİDE, çözüm önerisi), koşu devam eder, hiçbir şey yazılmaz" {
  krun kurulum_onizle -e kurulum_yazilim=nginx -e ansible_python_interpreter=/usr/local/bin/py-faketime
  [ "$status" -eq 0 ]
  [[ "$output" == *"UYARI sunucu saati kontrol makinesinden"* && "$output" == *"GERİDE"* ]]
  [[ "$output" == *"sudo date -u -s @"* && "$output" == *"chronyc makestep"* && "$output" == *"utility paketi"* ]]
  run lab sh -c 'test ! -e /srv/homelab && test ! -e /etc/kurulum && echo temiz'
  [ "$output" = temiz ]
}

@test "V04: native nginx — indeks boşken kur kendini toparlar (önizleme dahil)" {
  indeks_boz
  krun kurulum_onizle -e kurulum_yazilim=nginx
  [ "$status" -eq 0 ]
  indeks_boz
  krun kur -e kurulum_yazilim=nginx
  [ "$status" -eq 0 ]
  run lab sh -c 'dpkg -s nginx | grep -c "^Status: install ok installed"'
  [ "$output" = 1 ]
}

@test "V04: native mariadb ve redis — indeks boşken kur kendini toparlar" {
  indeks_boz
  krun kur -e kurulum_yazilim=mariadb
  [ "$status" -eq 0 ]
  indeks_boz
  krun kur -e kurulum_yazilim=redis
  [ "$status" -eq 0 ]
}

@test "V04: Docker taban — depo ZATEN ekli, indeks boş: yeniden kur kendini toparlar" {
  krun kur -e kurulum_yazilim=docker
  [ "$status" -eq 0 ]
  lab sh -c 'systemctl stop docker docker.socket containerd 2>/dev/null; apt-get remove -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1'
  indeks_boz
  run lab sh -c 'test -f /etc/apt/sources.list.d/docker.sources && ! dpkg -s docker-ce 2>/dev/null | grep -q "^Status: install ok installed" && echo hazir'
  [ "$output" = hazir ]
  krun kur -e kurulum_yazilim=docker
  [ "$status" -eq 0 ]
  run lab sh -c 'dpkg -s docker-ce | grep -c "^Status: install ok installed"; systemctl is-active docker'
  [ "${lines[0]}" = 1 ] && [ "${lines[1]}" = active ]
}

@test "ikinci kur docker/nginx changed=0 (toparlama idempotans bozmaz)" {
  krun kur -e kurulum_yazilim=docker
  [ "$(recap_changed)" = 0 ]
  krun kur -e kurulum_yazilim=nginx
  [ "$(recap_changed)" = 0 ]
}

@test "TEMİZ ÇIKTI: hiçbir koşuda beklenmeyen [WARNING] / [DEPRECATION WARNING] yok" {
  run beklenmeyen_uyarilar "$BATS_FILE_TMPDIR/hepsi.log"
  [ "$status" -eq 1 ]
}
