# sshpocket paket şablonu

[sshpocket](https://github.com/syhgorath/sshpocket) için **yeni bir paket yazmanın başlangıç noktası**. Çalışan, küçük ve salt okunur bir örnek içerir
(`bilgi` eylemi: sunucunun çekirdeğini, işletim sistemini ve çalışma süresini okur). Kendi paketinize dönüştürmek için dosyaları değiştirirsiniz;
sshpocket'e **kod eklemeniz gerekmez** (`ansible` ya da `script` runner'ı için): kilit dosyasına tek satır eklenir, menü, onaylar, kapılar ve geçmiş otomatik gelir.

Standart: [docs/package-standard.md](https://github.com/syhgorath/sshpocket/blob/main/docs/package-standard.md) (özellikle §12 kontrol listesi).

## 15 dakikada kendi paketiniz
1. **Kopyalayın** (GitHub'da *Use this template* ya da klonlayıp `.git`'i silin).
2. **`component.json`**: `id` (küçük harf, rakam, `-`), `name`, `description`, `inventory_group`; **`playbooks/*.yml`** içindeki `hosts:` aynı grubu kullanmalı.
3. **Eylemlerinizi yazın** (`actions`): her biri bir `ansible-playbook playbooks/<ad>.yml` komutudur.
   - `effects: []` = salt okunur. Değiştiren eylemlere `effects` (`installs-package`, `changes-config`, `destructive`), `requires_sudo`, `warnings` ve salt okunur bir `preview` ön koşulu (`requires`) ekleyin.
   - Sonuç göstermek istiyorsanız playbook tek bir satır yazar: `SSHPOCKET_RESULT <paket-id>.<eylem> anahtar=değer ...` (anahtarları `outputs.keys` listeleyin; değerler yalnızca `[A-Za-z0-9_.:+-]`, en çok 64 karakter).
4. **Değişkenler** (`vars`): tür, varsayılan, açıklama verin. **Parola/anahtar/token değişken OLAMAZ.** Hassas çıktı için `outputs.dir_var` (kullanıcı klasörüne yönlendirilir).
5. **Denetleyin:** `python3 -I tools/validate/component_validate.py . --strict` (❌ hata, ⚠️ uyarı; hedef: ikisi de yok).
6. **Sürüm:** `VERSION`, `component.json` `version` ve `CHANGELOG.md` başlığını güncelleyin, commit edin, `git tag -a vX.Y.Z`. Sonra:
   `PAKET_SIGNING_KEY=~/.ssh/<özel_anahtar> scripts/release.sh` → `dist/<id>-<sürüm>.tar.gz` + `.sig` (imza yayından önce kendi public anahtarıyla doğrulanır).
7. Dosyaları GitHub'da `vX.Y.Z` Release'ine yükleyin; sshpocket bakımcısı kilide yazar: `scripts/lock-component.sh <id> <sürüm> --repo <sahip>/<depo> --write` (tek satırlık PR).

> Güven modeli: sshpocket yalnızca **kendi kilit dosyasındaki, imzalı** paketleri çalıştırır. Üçüncü taraf paket desteklenmez; yeni paketi sshpocket bakımcısı imzalar ve kilitler.
> **Özel imza anahtarı asla** repoya, CI'a veya sohbete konmaz.

## Ansible yerine betik mi? (`runner: script`)
Basit işler (sağlık özeti, temizlik, tek ayar) için playbook yerine **betik** yazabilirsiniz. Çalışan örnek: [`ornekler/betik-paketi/`](ornekler/betik-paketi/) (`saglik`, önizlemeli `journal_temizle`).
- Betik **hedef sunucuda** çalışır; kontrol makinesinde yabancı kod çalışmaz. `cmd` = `scripts/<ad>.sh [argümanlar]`.
- Değişkenler betikte `SSHPOCKET_VAR_<AD>` olarak gelir; sonuç yine tek `SSHPOCKET_RESULT <id>.<eylem> k=v` satırıdır.
- `requires_sudo` yoksa betik stdin'den akar; varsa sudo parolası sudo isteminde girilir ve betik root'a ait kopyadan, SHA-256 doğrulanarak çalışır.
- `--dry-run` destekleyen betik için iki eylem tanımlayın (`*_onizle` + gerçek eylem, `requires` ile bağlı).
- Kökteki Ansible örneği **paketin kendisidir**; `ornekler/` yayın paketine girmez (`.gitattributes`).
- Ayrıntı: sshpocket `docs/package-standard.md` §7.

## İsteğe bağlı manifest alanları (sshpocket 3.6.20 ve sonrası)
Şablondaki küçük paket bunları kullanmaz; ihtiyacınız olursa [standardın](https://github.com/syhgorath/sshpocket/blob/main/docs/package-standard.md) ilgili bölümüne bakın. Doğrulayıcı hepsini tanır.
- **`requires_vars`** (eylem düzeyi): listedeki değişkenler değerler dosyasında boş/yoksa sshpocket eylemi ssh'a gitmeden ⛔ kapatır (örn. erişimi kilitleyebilecek `allow_from`). Standart §6.
- **`platform_choices` + `platform_var`** (üst düzey): sunucu eklerken sorulan tür listesi (`id`, `label`, `description`, `defaults`, `apply_vars`, `apply_warnings`); seçilen platformun `defaults` değerleri onayla yazılır. `onboarding_vars`: ilk açılışta sorulması gereken zorunlu değişkenler (`list[cidr]` için ağ editörü). Standart §6.
- **`outputs.findings`**: denetim eyleminin yazdığı bulgu dosyası (`bulgular.tsv`); sshpocket sunucu menüsünde 🔎 Bulgular olarak listeler. Standart §8.

## Dosya haritası
| Dosya | Ne işe yarar |
|---|---|
| `component.json` | Makine-okunur bildirim (sözleşme). Kimlik, profiller, eylemler, değişkenler |
| `playbooks/` | Eylemlerin çalıştırdığı playbook'lar |
| `ansible.cfg` | Çalışma dizini paket kökü; ayarlar buradan okunur (host key doğrulamasını kapatmayın, sshpocket zorlar) |
| `requirements.in` / `requirements.txt` | Denetleyici makinedeki Python bağımlılıkları. `.txt` **hash'li ve sabit sürümlü** olmalı (`pip-compile --generate-hashes --strip-extras --allow-unsafe -o requirements.txt requirements.in`) |
| `VERSION`, `CHANGELOG.md` | Sürüm üçlüsünün parçaları (`VERSION` = `component.json` = etiket) |
| `scripts/release.sh` | İmzalı paket üretir (geliştirici dosyası; pakete girmez) |
| `ornekler/` | Ek örnek paketler (`betik-paketi`: `runner: script`); yayın paketine girmez, CI `--strict` denetler |
| `tools/validate/` | sshpocket'in sözleşme doğrulayıcısı (**vendored kopya**, elle düzenlemeyin; özetler `VENDORED.md`'de, CI denetler) |
| `.gitattributes` | `export-ignore`: `.github/`, `tools/`, `scripts/` yayın paketine girmez |
| `.github/workflows/ci.yml` | PR'da doğrulayıcıyı, vendored özetleri ve `ansible-playbook --syntax-check`'i çalıştırır |

## Sık yapılan hatalar
- `ansible_distribution` gibi üst düzey değişkenler yerine **`ansible_facts['distribution']`** kullanın (ansible-core 2.24'te kalkıyor).
- Sonuç değerinde boşluk/özel karakter bırakmayın; `regex_replace('[^A-Za-z0-9_.:+-]', '_')` ile temizleyin.
- Değiştiren eylemi `preview` olmadan bırakmayın; önizlemenin **göstermediği** şeyleri `warnings`'e yazın.
- Geri alma/kurtarma yolu olmayan bir değişikliği belgelemeden yayınlamayın (kapsamı dürüstçe yazın).

## Yerel deneme
- Sözdizimi: `python3 -m venv .venv && .venv/bin/pip install --require-hashes --only-binary :all: -r requirements.txt && .venv/bin/ansible-playbook --syntax-check -i 'localhost,' playbooks/bilgi.yml`
- Gerçek sunucuda: sshpocket reposundaki **Docker LAB'ı** (systemd'li Ubuntu 26.04, `test/e2e/lab/`) çoğu akışı sunucusuz dener.

## Doğrulayıcıyı güncelleme
sshpocket'in doğrulayıcısı değişince: `tools/sync-validator.sh <sshpocket-dizini>` (kopyalar ve özetleri `VENDORED.md`'ye yazar).

Lisans: MIT.
