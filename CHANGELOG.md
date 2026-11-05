# Changelog

Biçim [Keep a Changelog](https://keepachangelog.com/) esas alınmıştır.

## [Unreleased]

## [0.1.0] - 2026-11-05

İlk sürüm. **Gerçek VM turu yapılmadan yayınlanmamalıdır** (aşağıdaki "Denenmedi").

### Eklendi
- Eylemler: `durum` (salt okunur), `preview` (`--check --diff`), `apply` (`yes-no` onay, `preview` ön koşul), `geri_yukle`.
- Saat dilimi (`utility_timezone`), sistem dili yalnızca `LANG` (`utility_locale`), NTP kaynakları (`utility_ntp_servers`, chrony `sources.d/utility.sources` drop-in'i; `chrony.conf`'a dokunulmaz).
- Değiştirmeden önce `/var/backups/utility/<UTC tarih>/` yedeği (dizin 0700, dosyalar 0600, `manifest.json`); yalnızca değişecek yollar. `geri_yukle` yalnızca katalogdaki dosyaları geri yazar.
- Ubuntu 26.04: `supported`. Debian 13: `planned` (playbook çalışır ve uyarır; sshpocket açmaz).
- Release araçları (`scripts/release.sh`, `release-publish.sh`, `check-consistency.py`) linux-hardening'den/şablondan uyarlandı; LAB e2e (`test/e2e/lab.bats`) ve yedek betiği birim testleri.

### Denendi
- `--strict` doğrulayıcı temiz; LAB (systemd'li Ubuntu 26.04 konteyneri) e2e 13/13, ikinci `apply` `changed=0`; aynı LAB Debian 13 konteyneri (`debian:trixie`) ile de geçti (VM değildir).

### Denenmedi
- Gerçek Ubuntu 26.04 VM (ubuntutest), gerçek Debian 13 VM, linux-hardening uygulanmış sunucuda birlikte çalışma, sshpocket menüsünden uçtan uca. LAB'da chrony servisi başlamadığı için NTP **senkronu** denenmedi.

### Bilinen sınırlar
- Debian 13'te chrony kurulumu, `systemd-timesyncd`'nin yerini alması ve `conf.d`/`sources.d` varlığı gerçek VM'de doğrulanmadı.
- NTP kaynakları dağıtımın varsayılanlarının yanına eklenir; varsayılanları kaldırmaz. NTS desteklenmez.
- Zamanlayıcılı geri alma yoktur; geri dönüş yalnızca `geri_yukle` (dosyalar) ile olur, paketler/üretilmiş locale'ler/servis durumu geri alınmaz.
