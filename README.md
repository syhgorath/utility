# utility

[sshpocket](https://github.com/syhgorath/sshpocket) paketi: sunucunun **saat dilimini**, **sistem dilini (`LANG`)** ve **NTP kaynaklarını (chrony)** menüden, önizleyerek, yedekleyerek ve onayla yönetir.
Düşük riskli, dar kapsamlı bir pakettir: ssh, ufw ve PAM'a dokunmaz, erişimi kesmez. Bu yüzden `linux-hardening`'deki zamanlayıcılı geri alma güvenlik ağı **yoktur**; yerine önizleme, yedek ve idempotans vardır.

> **Durum: v0.1.0, yayınlanmadı.** Aşağıdaki "Neyin denendiği" tablosu gerçeği söyler: gerçek VM turu henüz yapılmadı.

## Profiller
| Profil | Durum | Not |
|---|---|---|
| `ubuntu-26.04` | supported | LAB'da (Docker konteyneri) uçtan uca denendi; **gerçek VM turu bekliyor** |
| `debian-13` | **planned** | Playbook çalışır ve uyarı verir, ama sshpocket bu profili açmaz. Konteynerde denendi; chrony/systemd-timesyncd etkileşimi **gerçek Debian 13 VM'inde doğrulanmadı** |

Kapsam dışı (v0.1): Proxmox VE, Raspberry Pi, hostname, apt kaynakları, NTS, `makestep`, `LC_*`.

## Eylemler
| Eylem | Etki | Sudo | Ne yapar |
|---|---|---|---|
| `durum` | salt okunur | hayır | Tek satır: `SSHPOCKET_RESULT utility.durum timezone=… locale=… ntp_servis=… ntp_senkron=yes\|no offset_ms=… kaynak_sayisi=…` (saat dilimindeki `/` sonuçta `_` olur: `Europe_Istanbul`) |
| `preview` | salt okunur (`--check --diff`) | evet | Neyin değişeceğini dosya farkı ve plan adlarıyla gösterir: `degisen=<N> plan=timezone+locale+paket+ntp` |
| `apply` | `changes-config`, gerekirse `installs-package` | evet | `preview` ön koşul, `yes-no` onay. Önce **yedek**, sonra uygular: `degisen=<N> plan=… yedek=evet\|hayir` |
| `geri_yukle` | `changes-config` | evet | `yes-no` onay. Yedekten dosyaları geri yazar (aşağıdaki kapsam) |

## Değişkenler
| Değişken | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `utility_timezone` | string | boş | Örn. `Europe/Istanbul`. Boş = dokunma |
| `utility_locale` | string | boş | Yalnızca `LANG`, örn. `en_US.UTF-8`. Boş = dokunma. Gerekirse `locales` kurulur ve locale üretilir |
| `utility_ntp_servers` | list[string] | `[]` | En çok 8: `host`, `server host` veya `pool host` (`iburst` eklenir). Boş = dağıtım varsayılanı; dosya yazılmaz, chrony kurulmaz |
| `utility_backup` | bool | `true` | `false` = yedek alınmaz (ve `geri_yukle` o değişikliği geri alamaz) |
| `utility_restore_from` | string | boş | `geri_yukle` için yedek adı (`20261105T101500Z`); boş = en son yedek |

Parola/anahtar değişkeni yoktur.

## Neye sahiptir, neye dokunmaz
- **Sahip:** `/etc/localtime` ve `/etc/timezone`, `/etc/default/locale` (Ubuntu 26.04'te `/etc/locale.conf`'a bağdır) ve `/etc/locale.gen`, `/etc/chrony/sources.d/utility.sources`. Chrony yapılandırması değişince **chrony'yi yeniden başlatan tek taraf** bu pakettir.
- **Dokunmaz:** `chrony.conf` (yalnızca drop-in), ssh, ufw, auditd, PAM. `linux-hardening`'in `time` rolü yalnızca zaman **raporu** verir, dosya yazmaz.
- **NTP kaynakları eklenir, değiştirilmez:** Ubuntu 26.04'te dağıtımın varsayılan kaynakları `sources.d/ubuntu-ntp-pools.sources` içindedir ve **NTS** kullanır; utility bunları kaldırmaz, kendi `utility.sources`'ını yanına koyar. Yalnızca utility kaynaklarının kullanılmasını istiyorsanız, dağıtım dosyasını elle devre dışı bırakmanız gerekir (v0.1 bunu yapmaz).

## Yedek ve geri yükleme (kapsamı dürüstçe)
- `apply`, **değişecek** yolları değiştirmeden önce `/var/backups/utility/<UTC tarih>/` altına alır: dizin `0700`, dosyalar ve `manifest.json` `0600`. Değişiklik yoksa yedek alınmaz.
- `geri_yukle` **yalnızca dosyaları** geri yazar: `/etc/localtime`, `/etc/timezone`, `/etc/default/locale`, `/etc/locale.conf`, `/etc/locale.gen`, chrony `conf.d`/`sources.d` altındaki dosyalar. Yedek alındığında var olmayan dosya silinir. Başka bir yola yazmaz (kurcalanmış manifest dahil), bozuk yedeği özet kontrolüyle reddeder.
- **Geri almaz:** kurulan paketleri (`chrony`, `locales`), `locale-gen` ile üretilmiş locale'leri, çalışan servis durumunu, geçmiş log zaman damgalarını. Yedekten sonra elle yapılan değişikliklerin üzerine yazar.
- Zamanlayıcılı rollback yoktur. Yanlış NTP kaynağının en kötü sonucu saat senkronunun kaybıdır (ssh sertifikaları, TOTP, apt "Not live until" etkilenebilir); erişim kaybı değil.

## `linux-hardening` ile birlikte kullanım
Bilinen etkileşimler (kaynak: Ubuntu 26.04 chrony dosyaları ve linux-hardening belgeleri; **birlikte çalışma henüz gerçek sunucuda denenmedi**):
- auditd `/etc/localtime`, `adjtimex`, `settimeofday`, `clock_settime` izler: saat dilimi değişince `time-change` kaydı beklenir (`apply` uyarı yazar).
- `hardening_ufw_outgoing_deny` açıkken 123/udp çıkışı izinli olmalıdır; Ubuntu'nun varsayılan NTS kaynakları ayrıca 4460/tcp (NTS-KE) ister (`sources.d/ubuntu-ntp-pools.sources` bunu yazar). utility NTS yönetmez.

## Neyin denendiği
| Ne | Sonuç |
|---|---|
| `component_validate.py . --strict` | temiz (yerel) |
| LAB (Colima + systemd'li `ubuntu:26.04` konteyneri): `bats test/e2e/lab.bats` | 13/13: durum → preview (hiçbir şey yazmaz) → apply → ikinci apply `changed=0` → ikinci preview `degisen=0` → değişiklik → `geri_yukle` (`--check` dahil) → ilk yedeğe dönüş |
| Aynı LAB, `LAB_BASE=debian:trixie` konteyneri | 13/13 geçti; bu **Debian 13 VM doğrulaması değildir** (konteynerde `systemd-timesyncd` yok, chrony servisi başlamaz) |
| `bats test/backup.bats` (yedek betiği birim testleri), `test/run-all.sh` | yeşil |
| **Gerçek VM: ubuntutest (Ubuntu 26.04)** | **denenmedi** |
| **Gerçek VM: düz Debian 13** | **denenmedi** |
| **linux-hardening uygulanmış VM'de birlikte** | **denenmedi** |
| sshpocket menüsünden uçtan uca | **denenmedi** (kilit PR'ından sonra) |

LAB'ın sınırları: chrony.service konteynerde başlamaz (`ConditionVirtualization=!container`), bu yüzden LAB'da NTP **senkronu** denenemez; yalnızca yapılandırma, paket ve idempotans denenir. Çekirdek paylaşılır; `--privileged` yalnızca bu LAB içindir.

## Yerel deneme
```bash
python3 -I tools/validate/component_validate.py . --strict --unsigned   # sözleşme (hata ve uyarı olmamalı)
test/run-all.sh                                                          # hızlı testler (bats, release betikleri, tutarlılık)
bats test/e2e/lab.bats                                                   # LAB e2e (Docker/Colima; konteyneri sıfırdan kurar ve sonda kaldırır)
test/e2e/lab/up.sh && test/e2e/lab/run.sh preview -e utility_timezone=Europe/Istanbul   # elle: sshpocket'siz, playbook'u dener
```
`run.sh`, `component.json`'daki eylemin kendi komutunu çalıştırır; sshpocket'in menü/onay/ön koşul kapıları orada **yoktur**. Gerçek VM turu komutları: [docs/vm-turu.md](docs/vm-turu.md).

## Sürüm yayını (bakımcı)
`VERSION`, `component.json`, `CHANGELOG.md` tutarlı olmalı (`scripts/check-consistency.py`). Etiket, imza ve Release **bakımcı** işidir; imza anahtarı repoya/CI'a/sohbete konmaz:
```bash
PAKET_SIGNING_KEY=~/.ssh/<anahtar> scripts/release-publish.sh --dry-run   # ne yapacağını gösterir, hiçbir şey yapmaz
```
İmzalayıcı `linux-hardening` ile aynıdır (ad alanı `sshpocket-component`). Kilit satırını sshpocket reposunda `scripts/lock-component.sh utility <sürüm> --repo syhgorath/utility` ile ekleyin.

## Geliştirme
Şablon: [sshpocket-paket-sablonu](https://github.com/syhgorath/sshpocket-paket-sablonu). Standart: sshpocket `docs/package-standard.md`. `tools/validate/` vendored kopyadır (elle düzenlemeyin; `tools/sync-validator.sh`).

Lisans: MIT.
