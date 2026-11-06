# Changelog

Biçim [Keep a Changelog](https://keepachangelog.com/) esas alınmıştır.

## [0.1.1] - 2026-11-06

### Eklendi
- **Saat sapması düzeltme.** chrony çalışırken saat 1 sn'den fazla sapmışsa `preview` plana `saat` ekler ve nedenini yazar; `apply` kaynaklar erişilebilir olunca (en çok 60 sn bekler) TEK SEFERLİK `chronyc makestep` yapar ve eşik altına inmesini doğrular. Kalıcı `makestep` ayarı YAZILMAZ. Ölçülemezse (erişilebilir kaynak yok) uyarır; ölçüldü ama düzelmediyse hata verir. Kapatmak için `utility_ntp_makestep=false` (varsayılan `true`). Uyarı metinleri adımlamanın etkisini (log/cron/auditd `time-change`, ssh/TOTP) söyler.
- `durum`: `sapma_ms` ve `secili_kaynak` alanları. `ntp_senkron=yes` artık chrony çalışırken seçili kaynak ve sapma <= 1 sn gerektirir (önceden yalnızca `timedatectl`'e bakılırdı; snapshot'tan geri açılan, 13 gün geride bir VM'de yanıltıcı `yes` görülmüştü).
- Birim testleri `test/clock.bats` (sahte `chronyc`), LAB testleri (sahte `chronyc` ile).

### Düzeltildi
- `apply` ve `geri_yukle` saat dilimi dosyalarını değiştirince `systemd-timedated` önbelleği eski değeri tutuyordu (`timedatectl show -p Timezone` yanlış; `date` ve `/etc/localtime` doğruydu). Artık `systemctl try-restart systemd-timedated` yapılır. Gerçek Ubuntu 26.04 VM'de ve LAB'da yeniden üretildi; düzeltme yalnız LAB'da sınandı.

### Denenmedi
- Saat adımlama gerçek VM'de DENENMEDİ: LAB konteynerinde chronyd ve saat adımlama yoktur, testler SAHTE `chronyc` ile yalnızca betik/playbook akışını sınar. Elle `chronyc makestep`'in kaynaklar Reach alınca gerçek VM'de işe yaradığı gözlendi, otomatik yol gözlenmedi.

## [0.1.0] - 2026-11-05

İlk sürüm.

### Eklendi
- Eylemler: `durum` (salt okunur), `preview` (`--check --diff`), `apply` (`yes-no` onay, `preview` ön koşul), `geri_yukle`.
- Saat dilimi (`utility_timezone`), sistem dili yalnızca `LANG` (`utility_locale`), NTP kaynakları (`utility_ntp_servers`, chrony `sources.d/utility.sources` drop-in'i; `chrony.conf`'a dokunulmaz).
- Değiştirmeden önce `/var/backups/utility/<UTC tarih>/` yedeği (dizin 0700, dosyalar 0600, `manifest.json`); yalnızca değişecek yollar. `geri_yukle` yalnızca katalogdaki dosyaları geri yazar.
- Ubuntu 26.04 ve Debian 13: `supported` (Debian 13.7 tek gerçek VM'de, hardening'siz, auditd/ufw olmadan denendi).
- Proxmox VE koruması: `/usr/bin/pveversion` ya da `/etc/pve` varsa `--check` dahil durur (Proxmox VE 9 Debian 13 tabanlı olduğundan OS eşlemesinden geçerdi). Sahte `pveversion` ile LAB'da test edildi; gerçek Proxmox'ta denenmedi.
- Release araçları (`scripts/release.sh`, `release-publish.sh`, `check-consistency.py`) linux-hardening'den/şablondan uyarlandı; LAB e2e (`test/e2e/lab.bats`) ve yedek betiği birim testleri.

### Denendi
- `--strict` doğrulayıcı temiz; LAB (systemd'li Ubuntu 26.04 konteyneri) e2e 13/13, ikinci `apply` `changed=0`; aynı LAB Debian 13 konteyneri (`debian:trixie`) ile de geçti (VM değildir).

- Gerçek Ubuntu 26.04 VM (ubuntutest, linux-hardening'li, doğrudan playbook): `durum` → `preview` → `apply` → bağımsız doğrulama → ikinci `preview` `changed=0` → `geri_yukle` ✅ (timezone ve NTP drop-in'i; ayrıntı README).

- Gerçek Ubuntu 26.04 VM, ikinci tur: `tr_TR.UTF-8` ile `locale-gen` yolu, 2 NTP kaynağı, `ausearch -k time-change` kaydı (`/etc/localtime` CREATE/DELETE), ikinci `preview` `changed=0`, `geri_yukle` ✅. Geri yükleme üretilmiş locale'leri silmez (`locale -a` hâlâ `tr_TR.utf8`; beklenen).

- Gerçek Debian 13.7 VM (düz, hardening'siz): durum → preview → apply (chrony kuruldu, timesyncd kaldırıldı) → bağımsız doğrulama → ikinci preview `changed=0` → geri_yukle ✅; tırnaklı `LANG` doğru okundu, `LANGUAGE` satırı korundu.

### Denenmedi
- Gerçek Debian 13 VM'de ufw giden-reddi, hardening'li ve auditd'li Debian, Proxmox (gerçek); sshpocket menüsünden uçtan uca; `locales` paketinin gerçek VM'de kurulum yolu (VM'de zaten kuruluydu); 3'ten fazla NTP kaynağı; ufw giden-reddi açıkken davranış. LAB'da chrony servisi başlamadığı için LAB'da NTP **senkronu** denenmedi.

### Bilinen sınırlar
- Ubuntu 26.04'te doğrudan `ansible-playbook --ask-become-pass` sudo-rs yüzünden zaman aşımına düşer: `-e ansible_become_exe=/usr/bin/sudo.ws` (sshpocket menüsünde doğrulanmadı).
- NTP kaynakları eklenir, dağıtım varsayılanları silinmez/kapatılmaz; `prefer`/`minpoll` gibi seçenekler yok (v0.2 adayı).
- `durum`: chrony kurulu değilken `ntp_senkron=yes` görünebilir (timesyncd senkronu).
- NTP kaynakları dağıtımın varsayılanlarının yanına eklenir; varsayılanları kaldırmaz. NTS desteklenmez.
- Zamanlayıcılı geri alma yoktur; geri dönüş yalnızca `geri_yukle` (dosyalar) ile olur, paketler/üretilmiş locale'ler/servis durumu geri alınmaz.
