# utility

[sshpocket](https://github.com/syhgorath/sshpocket) paketi (kimlik `utility`; repo adı şimdilik `kurulum`): iki iş bir arada.
1. **Sunucu ayarları:** saat dilimi, sistem dili (`LANG`) ve **NTP** (chrony) menüden, önizleyerek, yedekleyerek ve onayla. Ayrıntı: [docs/saat-dil-ntp.md](docs/saat-dil-ntp.md) (eski `utility` v0.1.2 belgesi) ve aşağıdaki NTP bölümü.
2. **Kurulum merkezi:** **Docker taban kurulumu, nginx, MariaDB ve Redis** (her biri **native** ya da **Docker** modunda), önizleyerek, sürümü sabitleyerek ve **veriyi silmeden**.

> **Durum: v0.2.1 (v0.2.0 birleştirme sürümü yayında; 0.2.1 `ntp_durum` kaynak listesini ve `release-publish.sh` düzeltmesini ekler).** Eski `utility` paketi (v0.1.2) bu pakete taşındı. Kimlik `utility` olduğundan sonuç satırı öneki `utility.*` oldu (kurulum eylemleri artık `utility.kur` vb.). **Denenmedi (gerçek VM):** birleştirilmiş paket, `ntp_durum`/`ntp_ayarla`, chrony ile `systemd-timesyncd` birlikte etkinken davranış, `utility/durum` anahtar uyumunun sshpocket tarafında. Kurulum eylemleri için v0.1.0 notları geçerli: LAB tam, gerçek VM turu kısmen ([docs/vm-turu.md](docs/vm-turu.md)); V01–V05 düzeltmeleri ve hardening'li tur gerçek VM'de doğrulanmadı. Utility eylemleri v0.1.2'de Ubuntu 26.04 ve Debian 13.7'de gerçek VM'de denendi ([docs/saat-dil-ntp.md](docs/saat-dil-ntp.md)).

## Profiller
| Profil | Durum | Not |
|---|---|---|
| `ubuntu-26.04` | supported | Sunucu ayarları (utility eylemleri): LAB ve gerçek VM. Kurulum eylemleri: LAB'da (arm64 konteyner) ve **kısmen gerçek VM'de** (amd64, ubuntutest, doğrudan playbook, hardening'siz); VM turu sürüyor |
| `debian-13` | supported | **Yalnızca sunucu ayarları (utility eylemleri)**, Debian 13.7'de tek gerçek VM'de denendi. **Kurulum eylemleri (kur/yukselt/kaldir/kurulum_*) Debian 13'te DENENMEDİ**: `kurulum_planned_os` gereği ön kontrol "planned" der ve durur (aşağıdaki not) |

Proxmox VE bilerek reddedilir (`/usr/bin/pveversion` ya da `/etc/pve` varsa `--check` dahil durur); Raspberry Pi kapsam dışı.

## Eylemler
Sunucu ayarları (eski `utility`; eylem adları, anahtarlar ve davranış **değişmedi**):
| Eylem | Etki | Onay | Ne yapar |
|---|---|---|---|
| `durum` | salt okunur, sudo yok | – | `timezone=… locale=… ntp_servis=… ntp_senkron=… offset_ms=… kaynak_sayisi=… sapma_ms=… secili_kaynak=… saat_sapma_kontrolcuye_gore_sn=…`. **sshpocket'in sunucu ekleme sihirbazı ve bağlantı testi bunu çağırır**: anahtar adları korunur, yalnızca eklenebilir |
| `preview` | salt okunur (`--check --diff`) | – | Saat dilimi/locale/NTP planı: `degisen=<N> plan=…` |
| `apply` | `installs-package`, `changes-config` | `yes-no`, `preview` ön koşul | Önce yedek, sonra saat dilimi + locale + NTP + saat adımlama |
| `geri_yukle` | `changes-config` | `yes-no` | Yedekten dosyaları geri yazar |
| `ntp_durum` | salt okunur, sudo yok | – | **Yeni.** `durum`un NTP kısmının ayrıntılısı: `hizmetler=` (etkin zaman hizmetleri: chrony, systemd-timesyncd, ntp, ntpsec, ntpd-rs; yoksa `yok`), `ntp_kaynak_1..8=` (utility.sources'taki gerçek host adları; yalnız host, kullanılmayan anahtar yazılmaz), `yonetilen_kaynak=` (utility.sources satırı sayısı), `proxmox=evet\|hayir` |
| `ntp_ayarla` | `installs-package`, `changes-config` | `yes-no`, `preview` ön koşul | **Yeni.** Yalnızca NTP: chrony kurar, `utility_ntp_servers` kaynaklarını drop-in'e yazar, gerekirse tek seferlik saat adımlar; **saat dilimi ve locale'a dokunmaz**. Yedek alır (`geri_yukle` geri alır). Proxmox'ta `--check` dahil reddedilir |

Kurulum merkezi (eski `kurulum`; **eylem adları değişti**: sonuç öneki `utility.*`, `durum`/`preview` kurulum karşılıkları yeniden adlandırıldı):
| Eylem | Etki | Onay | Ne yapar |
|---|---|---|---|
| `kurulum_durum` | salt okunur | – | Ana klasör işareti, Docker durumu, kurulu yazılımlar ve portlar: `ana_durum=… docker=… kurulu=… portlar=…` (eski `kurulum/durum`) |
| `kurulum_onizle` | salt okunur (`--check --diff`) | – | `kur`'un aynı görevleri `--check` ile; `degisen=<N> yukseltme=evet\|hayir` (eski `kurulum/preview`; `kur`/`yukselt`/`kaldir` bunu ön koşul ister) |
| `kur` | `installs-package`, `changes-config` | `yes-no`, `kurulum_onizle` ön koşul | Seçili yazılımı kurar. İkinci çalıştırma `changed=0`. **Sürümü sessizce değiştirmez** |
| `yukselt` | + `destructive` | `type-server-name`, `kurulum_onizle` ön koşul | Yalnızca **docker** modunda, daha **yeni** sürüme; önce döküm/yedek. **Geri düşürme yok** |
| `kaldir` | `changes-config` | `yes-no`, `kurulum_onizle` ön koşul | Servisi durdurur/kaldırır; **veriye dokunmaz** |

Kurulum çıktısı tek satırdır: `SSHPOCKET_RESULT utility.<eylem> yazilim=… mod=… surum=… port=… degisen=… yukseltme=… gizli=<üretilen parola sayısı>`. Parola değeri hiçbir satıra yazılmaz. **Envanter grubu `utility`** (eski kurulum grubu `kurulum` idi).

**Ayar kartları (v0.2.1):** `component.json`'daki üst düzey `settings` alanı NTP sunucuları, saat adımlama, kontrol makinesinden saat, saat dilimi ve LANG için KeyLab'a kart tanımı verir (hangi değişken, hangi eylemle uygulanır, gerçek değer hangi durum anahtarından okunur). Ayarlar `setting_cards`'taki iki karta ayrılır: **Saat (NTP)** (üç NTP/saat ayarı) ve **Sistem** (saat dilimi, LANG). Saat kartı `ntp_durum`'dan bir sağlık özeti gösterir: uyarı yalnız senkron, sapma (1000 ms) ve kontrol makinesine farktan (300 sn) gelir; chrony ve seçili kaynak yalnız bilgidir. Paketin davranışını değiştirmez; kartları desteklemeyen KeyLab sürümleri bu alanları yok sayar. Boş NTP listesi sunucudaki `utility.sources`'a dokunmaz.

### NTP eylemleri (v0.2.0)
- **Tek sahip:** yalnızca chrony yazılır (`/etc/chrony/sources.d/utility.sources`, `chrony.conf`'a dokunulmaz). `systemd-timesyncd`/`ntp`/`ntpsec` **kapatılmaz**: biri chrony ile birlikte etkinse `ntp_durum` bunu `hizmetler=a+b` ile gösterir, karar sizindir. Debian 13'te chrony kurulumu timesyncd'yi paket çakışmasıyla kaldırmıştı (v0.1.2 VM turu); Ubuntu 26.04'te birlikte davranışı **denenmedi**.
- **Değişkenler:** mevcut `utility_ntp_servers`, `utility_ntp_makestep`, `utility_ntp_clock_from_controller` (yeni değişken yok).
- **Proxmox VE:** `ntp_ayarla` (ve diğer yazan eylemler) `/usr/bin/pveversion` ya da `/etc/pve` varsa **`--check` dahil reddedilir** ve hiçbir şey değişmez: Proxmox kümelerinde (corosync) saat ayarı kritiktir, bu pakette yok. `ntp_durum` yalnız okur ve `proxmox=evet` der. Proxmox bu sürümde kapsam dışıdır.
- `ntp_ayarla` için `preview` ön koşuldur; `preview` tüm planı (saat dilimi, locale, NTP) gösterir, `ntp_ayarla` yalnız NTP kısmını uygular.

## Değişkenler (bugünkü sshpocket ile çalışır; katalog/form sshpocket tarafında sonra gelir)
Sunucu ayarları değişkenleri (`utility_timezone`, `utility_locale`, `utility_ntp_servers`, `utility_ntp_clock_from_controller`, `utility_ntp_makestep`, `utility_backup`, `utility_restore_from`): tür, varsayılan ve anlamları [docs/saat-dil-ntp.md](docs/saat-dil-ntp.md) içinde.

Kurulum değişkenleri:
| Değişken | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `kurulum_yazilim` | enum | `docker` | `docker` (taban) · `nginx` · `mariadb` · `redis`. Eylemler seçili yazılım için çalışır |
| `kurulum_mod` | enum | `native` | `native` (apt) · `docker`. `docker` yazılımı için yok sayılır. Bir yazılım için **tek mod** |
| `kurulum_ana_klasor` | path | `/srv/homelab` | Docker uygulamalarının klasörü; sunucu başına bir kez (aşağıda) |
| `kurulum_docker_kaynak` | enum | `resmi` | `resmi` (download.docker.com) · `dagitim` (docker.io) |
| `kurulum_dis_erisim` | bool | `false` | Eski genel seçim, yalnız erişim `otomatik` iken: `false` = `127.0.0.1`; `true` = `0.0.0.0` (**uyarı çıkar**, ufw'ye yazılmaz) |
| `kurulum_<yz>_erisim` | enum | `otomatik` | `ic` (yalnız iç ağ, port yok; yalnız docker) · `sunucu` (`127.0.0.1`) · `agdan` (`0.0.0.0`). `otomatik`: kurulu uygulama durumunu korur; yeni docker mariadb/redis `ic`, diğerleri `sunucu` (`kurulum_dis_erisim=true` ise `agdan`) |
| `kurulum_docker_ag` | string | `kurulum` | Docker uygulamalarının ortak ağı; docker uygulaması kuruluyken değiştirilemez |
| `kurulum_<yz>_port` | int | 8080 / 3306 / 6379 | Sunucuya yayınlanan port |
| `kurulum_<yz>_surum` | enum | 1.30.6 / 11.4.13 / 7.4.12 | Küratörlü imaj sürümü (docker modu; **latest yok**) |
| `kurulum_<yz>_imaj_ozel` | string | boş | Listede olmayan sürüm: `nginx:1.31.8`. **Denenmemiştir**; `latest`/etiketsiz reddedilir |

Küratörlü sürümler (artan; paket sürümüyle gelir): nginx `1.30.6`, `1.31.8` · mariadb `10.11.19`, `11.4.13`, `11.8.9` · redis `7.2.17`, `7.4.12`, `8.2.11`, `8.4.8`. Parola/anahtar değişkeni **yoktur**.

## Nasıl çalışır (kısa)
- **Docker kontrolü:** kurulu değil → `kurulum_yazilim=docker` ile kurulur; apt'ten kurulu (docker-ce ya da docker.io) → **dokunulmaz**; snap/paket dışı → uyarı, dokunulmaz ve Docker modu çalışmaz. Kullanıcı `docker` grubuna **eklenmez** (root-eşdeğeri); komutlar sudo ile. `daemon.json` ve `/var/lib/docker` değişmez. Docker modu için Docker önceden kurulu olmalı (uygulama kurulumu Docker'ı kendiliğinden kurmaz).
- **Docker kaynağı:** varsayılan Docker'ın resmi apt deposu. Depo anahtarı pakette gelir (`roles/docker_taban/files/docker.asc`), parmak izi sabit (`9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`, testle denetlenir); ağdan anahtar indirilmez. Yedek yol `kurulum_docker_kaynak=dagitim`.
- **Ana klasör:** sunucuda `/etc/kurulum/ana` (yol) ve `<ana>/.kurulum` (JSON işaret: kurulu yazılımlar, mod, sürüm, port, veri yolu) **gerçek kaynaktır**. Yerel `kurulum_ana_klasor` farklıysa değiştiren eylemler **durur** ("ana klasör sunucuda X, yerelde Y"), sessiz düzeltme yok. Yol kuralları: mutlak, boşluk/özel karakter yok, `/ /etc /usr /var /srv …` kökleri ve `/var/lib/docker` altı yasak, tmpfs değil, dizin 0750 root. Sonradan taşıma v0.1'de yok.
- **Docker modu:** `<ana>/<yazılım>/compose.yml` şablondan, `docker compose config` ile doğrulanır; veri `<ana>/<yazılım>/data` (bind-mount; adlandırılmış volume ve `down -v` yok); ortak ağ `kurulum` (`kurulum_docker_ag`); yayın `kurulum_<yz>_erisim`'e göre (yeni mariadb/redis port yayınlamaz, nginx `127.0.0.1`). Konteyner adı `kurulum-<yazılım>`.
- **Gizli değerler:** `<ana>/<yazılım>/.env` (0600); parola **sunucuda** `/dev/urandom`'dan, yalnızca yoksa üretilir; `no_log`. `<ana>/.env` yalnızca gizli olmayan bağlantı anahtarlarını taşır (`NGINX_HOST`, `MARIADB_PORT`, `REDIS_HOST_PORT` …): native `127.0.0.1`, docker servis adı.
- **Native:** nginx (kendi sitesi `sites-available/kurulum`, dağıtım varsayılan **bağı** devre dışı, dosya silinmez), MariaDB (`99-kurulum.cnf`: bind/port; root `unix_socket`, parola yok), Redis (`redis.conf` satırları yedekli; parola `requirepass`). Veri dağıtım yerinde (`/var/lib/mysql`, `/var/lib/redis`, `/var/www/html`). Zaten kurulu ama kayıtsız paket varsa **durur**. Paketin kurulum betiği servisi varsayılan portta (80/3306/6379) kısaca başlatır; o port doluysa kurulum başlamadan durur.
- **Port çakışması:** `ss` + işaret dosyası; "3306 portu mariadb uygulamasına verilmiş, boş port önerisi: 3307".
- **Yeniden çalıştırmada toparlanma:** paket indeksi bayat/boşsa (`apt-cache policy` adayı yok) `kur` indeksi yeniler; yarım kalan koşudan sonra `kur`'u tekrar çalıştırmak yeterlidir.
- **Saat sapması:** sunucu saati kontrol makinesinden 1 saatten fazla farklıysa (`apt` "Release file ... is not valid yet" der) koşu başında net bir UYARI ve çözüm önerisi çıkar; koşu durmaz.
- **Eşzamanlılık:** sunucuda `/run/kurulum.lock` üzerinde `flock`; ikinci koşu durur. Tutucu süreç en geç 30 dk sonra kendiliğinden düşer.

## Native ve Docker modu: farklar (gerçek VM'de görüldü)
- **Modlar arası veri taşıma YOKTUR.** Docker modunun verisi `<ana>/<yazılım>/data`, native modun verisi dağıtım yerindedir (`/var/lib/mysql`, `/var/lib/redis`). `kaldir` ile modu değiştirince eski modun verisi **kullanılmaz** (silinmez, orada durur); taşımayı kendiniz yaparsınız.
- **Sürümler aynı değildir:** native, dağıtım paketinin sürümünü verir (Ubuntu 26.04 VM'de nginx 1.28.3, MariaDB 11.8.6, Redis 8.0.5); docker modu küratörlü sabit etiketi (örn. Redis 7.4.12). Aynı yazılımın iki modu aynı sürümü vermez.
- **Ortak `.env` anahtarları aynı, değerleri moda göre değişir:** `NGINX_HOST`/`_PORT` docker modunda servis adı ve konteyner portu (`nginx`, `80`), native modda `127.0.0.1` ve yayınlanan port (`8080`). Yayınlanan port her iki modda `<YZ>_HOST_PORT`'tur (docker'da erişim `ic` ise bu satır yoktur). Mod değişince tüketicilerin bu değerleri yeniden okuması gerekir.
- **`kaldir` ortak `<ana>/.env`'deki o yazılımın bağlantı anahtarlarını siler** (`<YZ>_HOST`, `_PORT`, `_HOST_PORT`; sır değil); yeniden `kur` yazar. Gizli `<ana>/<yazılım>/.env` (parola) silinmez: yeniden kur ve mod değişimi aynı parolayı kullanır.

## Ağ erişimi, ufw ve linux-hardening
`kurulum` ufw'ye **yazmaz** (tek sahibi linux-hardening).
- **Docker'ın yayınladığı port ufw kurallarına TAKILMAZ** (LAB'da Docker 29.1.3 ve 29.10.1 ile doğrulandı: ufw "deny incoming" iken `0.0.0.0` yayınına uzaktan erişildi). `agdan` seçiliyse port ağdaki herkese açıktır; ufw kuralı eklemek kısıtlamaz. `DOCKER-USER` ile kısıtlama denenmedi.
- **Native** servis `agdan` ise çıktı, `servers/<ad>/linux-hardening.vars` içindeki `hardening_ufw_extra_allow_host` listesine eklenecek kuralı **önerir** (`from <yönetim ağı> to any port N proto tcp`, `any` değil). Ansible liste değişkenlerini birleştirmez, üzerine yazar: öneriyi mevcut listeye siz eklersiniz.
- **`ic` (yalnız iç ağ)** sunucudan yalıtım değildir: aynı ağdaki her konteyner (nginx'te parola yok) ve sunucunun kendisi (konteyner IP'siyle) erişir. Kurulu uygulamayı `ic` yapmak konteyneri yeniden yaratır; `127.0.0.1`'den bağlananlar kopar.
- `127.0.0.1` yayını Docker 28 öncesinde aynı yerel ağdaki makinelerden erişilebiliyordu (Docker belgesi; bu pakette denenmedi).
- Hardening'le birlikte kullanım **VM'de denenmedi** (docs/vm-turu.md "Hardening turları"): `hardening_kernel_modules_disabled=true` Docker'ı bozar (kurulum sonra); `hardening_ufw_outgoing_deny` açıksa `apt` ve `docker pull` kapanır; `/tmp` noexec ve AppArmor'un MariaDB'ye etkisi doğrulanmadı.

## Yükseltme, kaldırma ve geri alma kapsamı (dürüstçe)
- **Yükseltme (`yukselt`)** yalnızca docker modunda ve daha yeni sürüme: önce döküm/yedek (`<ana>/<yazılım>/yedek/<tarih>/`, dizin 0700, dosya 0600; MariaDB `mariadb-dump --all-databases`, Redis `SAVE` + veri kopyası, nginx web kökü ve compose.yml), sonra yeni imaj çekilir, sonra compose güncellenir. **Geri düşürme yoktur**; eski sürüme dönmek için yedeği kendiniz geri yüklersiniz (bu paket geri yüklemeyi yapmaz). **Native sürüm yükseltme v0.1'de yok** (apt'i kendiniz yönetin).
- **Kaldır (`kaldir`)** veriye dokunmaz: docker modunda `compose down` (`-v` yok); veri klasörü, `.env` (parola) ve `compose.yml` kalır. Native'de servis durur/devre dışı kalır, paket `apt remove` ile çıkar (**purge yok**), yapılandırma ve veri kalır. Kaldırılan yazılım işarette `kaldirilan` altında kalır; yeniden `kur` aynı veriyi ve aynı parolayı kullanır. Docker taban kaldırma v0.1'de yok.
- **Geri almaz:** kurulan Docker/apt paketlerini, çekilmiş imajları, oluşturulan `kurulum` Docker ağını. Zamanlayıcılı geri alma güvenlik ağı yoktur (ssh/ufw/PAM'a dokunulmaz, erişimi kesmez).

## Neyin denendiği
Ayrıntı sonuçlar CHANGELOG'dadır. Özet:
| Ne | Sonuç |
|---|---|
| `component_validate.py . --strict --unsigned` (`git archive` arşivi) | temiz |
| LAB (Colima + systemd'li `ubuntu:26.04` arm64 konteyneri, iç içe Docker): `lab-docker.bats` / `lab-native.bats` / `lab-preview.bats` / `lab-apt.bats` | 21/21, 11/11, 8/8 ve 7/7: idempotans, yükseltmede veri duruyor, kaldır veriyi bırakır, parola sızmıyor (ayrıntı CHANGELOG) |
| `test/run-all.sh` (statik desen denetimi, release betikleri, tutarlılık) | yeşil |
| **Gerçek VM** ubuntutest (Ubuntu 26.04 **amd64**, hardening'siz, doğrudan playbook) | ✅ Docker taban (kur, ikinci kur changed=0); docker modu nginx/MariaDB/Redis kur + ikinci kur changed=0, parola sızıntısı 0 eşleşme, **yükseltme** (MariaDB 10.11.19→11.4.13 veri duruyor, Redis 7.2.17→7.4.12 anahtar duruyor, nginx 1.30.6→1.31.8), **kaldır** (veri/.env/compose kalır; Redis yeniden kur veri ve parolayı korudu); **native** nginx/MariaDB/Redis kur + ikinci kur changed=0. Ayrıntı CHANGELOG |
| Gerçek VM: V04 (indeks toparlama) ve V05 (saat sapması uyarısı) düzeltmeleri — LAB'da sınandı (faketime), VM'de **denenmedi** | **denenmedi** |
| Gerçek VM: hardening'li iki sıralı tur, native Redis'te yeni parola üretimi, düzeltilmiş native Redis `preview`, sshpocket menüsü | **denenmedi** |
| Debian 13 (konteyner dahil); `kurulum_docker_kaynak=dagitim` | **denenmedi** (yalnızca Debian deposunun varlığı `apt -s` ile görüldü). Profil `planned` kalır; v0.1.0 yalnızca Ubuntu 26.04 içindir |
| amd64 (LAB arm64) | **denenmedi** |

## Geliştirme
```bash
python3.13 -m venv .venv && .venv/bin/pip install --require-hashes --only-binary :all: -r requirements.txt
python3 -I tools/validate/component_validate.py . --strict --unsigned
test/run-all.sh
LAB_CA_FILE=<gerekirse kök sertifika.pem> bats test/e2e/lab-docker.bats test/e2e/lab-native.bats test/e2e/lab-preview.bats test/e2e/lab-apt.bats   # Colima/Docker gerekir
```
LAB notu: iç içe Docker için `/var/lib/docker` ve `/var/lib/containerd` ayrı volume'dür (yalnızca LAB; gerçek VM'de gerekmez). Ağda TLS'i araya giren bir güvenlik yazılımı varsa kök sertifikası yalnızca LAB konteynerine eklenir (`LAB_CA_FILE`); doğrulama kapatılmaz, paket buna bağımlı değildir.
Yayın: `scripts/release.sh` / `release-publish.sh` (imza anahtarı ve yayın **kullanıcıdadır**). `release-publish.sh` Release doğrulandıktan sonra imzalı paket indeksini (`syhgorath/sshpocket-index`, `SSHPOCKET_INDEX_DIR`) günceller; normal sürümde `components.lock` PR'ı **gerekmez**. İndeks hatası Release'i geçersiz kılmaz: `index-publish.sh` tek başına yeniden çalıştırılabilir. İndeks deposunda yalnızca yerel commit oluşur, push kullanıcıdadır.
