#!/usr/bin/env python3
"""component.json, VERSION, CHANGELOG, README profil tablosu ve playbook/rol değişken kullanımı arasındaki tutarlılığı denetler.

Kullanım (repo kökünde):  python3 -I scripts/check-consistency.py        (yalnızca standart kütüphane)
Hata varsa çıkış kodu 1. linux-hardening/scripts/check-consistency.py'nin kurulum'a uyarlanmış, çok daha küçük karşılığıdır.

Kurallar:
  - VERSION = component.json version; CHANGELOG.md'de '## [<sürüm>]' başlığı var.
  - Profil eşlemesi: component.json'daki supported profiller roles/common/defaults'taki utility_supported_os ile,
    planned profiller utility_planned_os ile BİREBİR aynı olmalı. Kurulum eylemlerinin kapsamı (roles/ortak: kurulum_supported_os,
    kurulum_planned_os) manifestin supported+planned profillerinin altkümesi olmalıdır (Debian 13'te kurulum planned olabilir).
  - README.md her profil için bir satır içerir.
  - component.json'daki her değişken, bir rolün defaults'ında tanımlıdır ve türü/varsayılanı uyuşur.
  - Her eylemin sonuç anahtarları, playbook'taki SSHPOCKET_RESULT satırında yazılır.
  - Uygulama okumaları (docker_durum, <uyg>_durum): salt okunur, yalnız kendi uygulamasının anahtarları; playbook sonuç satırı beyan edilenle birebir aynı.
  - Kart özeti ve ayar state'i var olan bir eylemin beyan ettiği anahtarı okur; uygulama kartları kendi okumasına bağlıdır.
  - proxy yalnız kendi anahtarlarını bildirir ve kurulu/portlar listelerine girmez (kurulum_ozet_disi).
  - Port sahibi uygulamaların kartı <uyg>_duvar'ı beklentisiz, <uyg>_duvar_engel'i ok=hayir ile gösterir.
  - kurulum_durum genel özettir (kurulu, portlar, her uygulamanın <uyg>_kurulu'su); kurulu/portlar'ın en uzun hali 64 karaktere sığar.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
errors = []


def err(msg):
    errors.append(msg)


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


comp = json.loads(read("component.json"))
version = read("VERSION").strip()
if comp.get("version") != version:
    err(f"VERSION ({version}) ile component.json version ({comp.get('version')}) aynı değil")
if not re.search(rf"^## \[{re.escape(version)}\]", read("CHANGELOG.md"), re.M):
    err(f"CHANGELOG.md içinde '## [{version}]' başlığı yok")

# profiller <-> rol varsayılanları (yalnızca "anahtar: { Dagitim: ["x"] }" tek satırlık biçim)
DEFAULTS_FILE = {"utility_": "roles/common/defaults/main.yml", "kurulum_": "roles/ortak/defaults/main.yml"}


def os_map(name):
    rel = DEFAULTS_FILE[name.split("_")[0] + "_"]
    m = re.search(rf"^{name}:\s*\{{(.*)\}}", read(rel), re.M)
    if not m:
        err(f"{rel} içinde {name} yok")
        return set()
    return {(d, v) for d, vs in re.findall(r'(\w+):\s*\[([^\]]*)\]', m.group(1)) for v in re.findall(r'"([^"]+)"', vs)}


DIST = {"ubuntu": "Ubuntu", "debian": "Debian"}
have = {"supported": set(), "planned": set()}
for p in comp.get("profiles", []):
    m = re.fullmatch(r"([a-z]+)-([0-9][0-9.]*)", p["id"])
    if not m or m.group(1) not in DIST:
        err(f"profil id'si '<dagitim>-<surum>' (ubuntu|debian) olmalı: {p['id']}")
        continue
    if p["status"] not in have:
        err(f"profil {p['id']}: bilinmeyen status {p['status']!r}")
        continue
    have[p["status"]].add((DIST[m.group(1)], m.group(2)))
    if p["id"] not in read("README.md"):
        err(f"README.md profil {p['id']} satırını içermiyor")
for status, name in (("supported", "utility_supported_os"), ("planned", "utility_planned_os")):
    want = os_map(name)
    for item in sorted(want - have[status]):
        err(f"{name} içinde {item} var ama component.json'da {status} profil yok")
    for item in sorted(have[status] - want):
        err(f"component.json {status} profil {item} {name} içinde yok")

kurulum_kapsam = os_map("kurulum_supported_os") | os_map("kurulum_planned_os")
for item in sorted(kurulum_kapsam - (have["supported"] | have["planned"])):
    err(f"kurulum kapsamındaki {item} component.json profillerinde yok")

# değişkenler <-> rol varsayılanları
role_defaults = "\n".join(p.read_text(encoding="utf-8") for p in sorted((ROOT / "roles").glob("*/defaults/main.yml")))
for v in comp.get("vars", []):
    m = re.search(rf"^{re.escape(v['name'])}:\s*(.*?)\s*(#.*)?$", role_defaults, re.M)
    if not m:
        err(f"{v['name']} hiçbir rolün defaults/main.yml dosyasında tanımlı değil")
        continue
    raw = m.group(1)
    default = v.get("default")
    expected = {True: "true", False: "false"}.get(default) if isinstance(default, bool) else None
    if isinstance(default, bool) and raw != expected:
        err(f"{v['name']}: defaults ({raw}) ile component.json varsayılanı ({expected}) uyuşmuyor")
    elif isinstance(default, str) and raw != json.dumps(default):
        err(f"{v['name']}: defaults ({raw}) ile component.json varsayılanı ({json.dumps(default)}) uyuşmuyor")
    elif isinstance(default, list) and raw != "[]" and default == []:
        err(f"{v['name']}: defaults ({raw}) ile component.json varsayılanı ([]) uyuşmuyor")

# int varsayılanlar ve küratörlü sürümler (enum values == kurulum_katalog.<yz>.surumler; varsayılan listede olmalı)
for v in comp.get("vars", []):
    if v.get("type") == "int":
        m = re.search(rf"^{re.escape(v['name'])}:\s*(\d+)", role_defaults, re.M)
        if not m or int(m.group(1)) != v.get("default"):
            err(f"{v['name']}: defaults ile component.json int varsayılanı uyuşmuyor")
    mm = re.fullmatch(r"kurulum_(nginx|mariadb|redis|proxy)_surum", v["name"])
    if mm:
        cat = re.search(rf"^  {mm.group(1)}:\n(?:    .*\n)*?    surumler: \[([^\]]*)\]", role_defaults, re.M)
        listed = re.findall(r'"([^"]+)"', cat.group(1)) if cat else []
        if listed != v.get("values"):
            err(f"{v['name']}: enum values ({v.get('values')}) kurulum_katalog surumler ({listed}) ile aynı değil")
        if v.get("default") not in listed:
            err(f"{v['name']}: varsayılan {v.get('default')!r} küratörlü listede yok")
        if "latest" in listed or any(not re.fullmatch(r"\d+\.\d+\.\d+", x) for x in listed):
            err(f"{v['name']}: küratörlü sürümler sabit x.y.z olmalı (latest yok)")

# eylemler: sonuç anahtarları playbook'ta
for name, a in comp["actions"].items():
    out = a.get("outputs") or {}
    if out.get("format") != "keyvalue-line":
        continue
    pb = re.search(r"playbooks/(\S+\.yml)", a["cmd"])
    text = read(f"playbooks/{pb.group(1)}") if pb else ""
    for k in out.get("keys", []):
        if not re.search(rf"\b{re.escape(k)}=", text):
            err(f"eylem {name}: sonuç anahtarı '{k}' playbook'ta yazılmıyor")
    if f"SSHPOCKET_RESULT {comp['id']}.{name}" not in text:
        err(f"eylem {name}: playbook 'SSHPOCKET_RESULT {comp['id']}.{name}' satırını yazmıyor")

# uygulama okumaları ve kart bağları. Uygulama kimlikleri küratörlü katalogdan gelir: yeni uygulama eklenince okuması ve sınır hesabı da istenir.
katalog = re.search(r"^kurulum_katalog:\n((?:[ #].*\n|\n)+)", read("roles/ortak/defaults/main.yml"), re.M)
yazilimlar = re.findall(r"^  ([a-z0-9_]+):\s*$", katalog.group(1), re.M) if katalog else []
if not yazilimlar:
    err("roles/ortak/defaults/main.yml: kurulum_katalog uygulamaları okunamadı")
uygulamalar = ["docker"] + yazilimlar
# genel özetin kurulu/portlar listelerine girmeyen uygulamalar (64 karakter sınırı)
m = re.search(r"^kurulum_ozet_disi: \[([a-z0-9_, ]*)\]", read("roles/ortak/defaults/main.yml"), re.M)
ozet_disi = [x.strip() for x in m.group(1).split(",") if x.strip()] if m else []
if ozet_disi != ["proxy"]:
    err("roles/ortak/defaults/main.yml: kurulum_ozet_disi [proxy] olmalı (yeni uygulama kurulu/portlar listelerine eklenmez; sınır dolu)")
if read("roles/port_kaydi/tasks/durum.yml").count("item.key in kurulum_ozet_disi") + read("roles/port_kaydi/tasks/durum.yml").count("item.key not in kurulum_ozet_disi") != 2:
    err("roles/port_kaydi/tasks/durum.yml: kurulum_ozet_disi uygulamaları kurulu/portlar listelerinden çıkarılmalı")
OZEL_ANAHTAR = {"docker": ["docker_kurulu", "docker_servis", "docker"],
                "proxy": ["ana_durum"] + [f"proxy_{k}" for k in ("kurulu", "mod", "port", "surum", "yonetim", "adres", "duvar")]}
actions = comp["actions"]


def keys_of(name):
    return (actions.get(name, {}).get("outputs") or {}).get("keys", [])


def sonuc_anahtarlari(name):
    """playbooks/<name>.yml sonuç satırının ('SSHPOCKET_RESULT' ile başlayan katlanmış msg bloğu) yazdığı anahtarlar, yazılış sırasıyla."""
    m = re.search(rf"^ +SSHPOCKET_RESULT {re.escape(comp['id'])}\.{name}\b.*\n(?:          .*\n?)*", read(f"playbooks/{name}.yml"), re.M)
    return re.findall(r"(?<![A-Za-z0-9_.])([a-z][a-z0-9_]*)=", m.group(0)) if m else []


for uyg in uygulamalar:
    ad = f"{uyg}_durum"
    beklenen = OZEL_ANAHTAR.get(uyg, ["ana_durum"] + [f"{uyg}_{k}" for k in ("kurulu", "mod", "port", "surum", "erisim", "duvar", "duvar_engel")])
    a = actions.get(ad)
    if a is None or not (ROOT / f"playbooks/{ad}.yml").is_file():
        err(f"uygulama {uyg}: salt okunur {ad} eylemi ve playbooks/{ad}.yml olmalı")
        continue
    if a.get("effects") != [] or a.get("confirm") != "none":
        err(f"eylem {ad}: salt okunur olmalı (effects [], confirm none)")
    if a.get("cmd") != f"ansible-playbook playbooks/{ad}.yml":
        err(f"eylem {ad}: cmd kendi playbook'unu çalıştırmalı")
    if a.get("requires_sudo") is not (uyg != "docker"):
        err(f"eylem {ad}: requires_sudo yanlış (işaret dosyası okuyan sudo ister; docker_durum istemez)")
    if keys_of(ad) != beklenen:
        err(f"eylem {ad}: yalnız kendi anahtarlarını bildirmeli; beklenen {beklenen}, gelen {keys_of(ad)}")
    if sonuc_anahtarlari(ad) != beklenen:
        err(f"playbooks/{ad}.yml sonuç satırı yalnız kendi anahtarlarını yazmalı; beklenen {beklenen}, gelen {sonuc_anahtarlari(ad)}")
    if uyg != "docker":
        pb = read(f"playbooks/{ad}.yml")
        if re.findall(r"^    k_d_yz:\s*(\S+)\s*$", pb, re.M) != [uyg] or "loop" in pb:
            err(f"playbooks/{ad}.yml yalnız {uyg} uygulamasını okumalı (k_d_yz: {uyg}, döngü yok)")

for c in comp.get("setting_cards", []):
    s = c.get("summary")
    if c["id"] in uygulamalar and (not s or s.get("action") != f"{c['id']}_durum"):
        err(f"kart {c['id']}: summary.action {c['id']}_durum olmalı")
    if s:
        for item in s.get("items", []):
            if item.get("key") not in keys_of(s.get("action")):
                err(f"kart {c['id']}: özet anahtarı '{item.get('key')}' {s.get('action')} çıktısında yok")
# güvenlik duvarı: portu olan her uygulama kartı değeri gösterir; uyarıyı yalnız <uyg>_duvar_engel verir (KeyLab özet öğesi tek beklenen değer taşır:
# <uyg>_duvar'a 'ok' yazılırsa 'atlanir' gibi sorun olmayan değerler de uyarı olur)
for c in comp.get("setting_cards", []):
    if c["id"] not in yazilimlar:
        continue
    ogeler = {i.get("key"): i for i in (c.get("summary") or {}).get("items", [])}
    duvar, engel = ogeler.get(f"{c['id']}_duvar"), ogeler.get(f"{c['id']}_duvar_engel")
    if duvar is None or "ok" in duvar or "max_abs" in duvar:
        err(f"kart {c['id']}: özet {c['id']}_duvar öğesini beklentisiz göstermeli")
    # proxy portu docker yayınıdır: ufw onu engelleyemez, engel uyarısı yoktur
    if c["id"] != "proxy" and (engel is None or engel.get("ok") != "hayir"):
        err(f"kart {c['id']}: özet {c['id']}_duvar_engel öğesi ok=hayir olmalı (uyarı yalnız engelde)")
    if len(ogeler) > 6:
        err(f"kart {c['id']}: özet en çok 6 öğe taşır")
for uyg in uygulamalar:
    if uyg not in {c["id"] for c in comp.get("setting_cards", [])}:
        err(f"uygulama {uyg}: setting_cards kartı yok")
for st in comp.get("settings", []):
    state = st.get("state")
    if not state:
        continue
    if st.get("card") in uygulamalar and state.get("action") != f"{st['card']}_durum":
        err(f"ayar {st['id']}: state.action {st['card']}_durum olmalı")
    for k in state.get("keys") or [state.get("key")]:
        if k not in keys_of(state.get("action")):
            err(f"ayar {st['id']}: state anahtarı '{k}' {state.get('action')} çıktısında yok")

# otomatik yönetim kararı yalnız IPv4 adreslerine bakar: 81 yalnız IPv4'te yayınlanmalı (IPv6 yayını eklenirse karar da IPv6'yı değerlendirmeli)
sablon = read("roles/proxy/templates/compose.yml.j2")
yayinlar = re.findall(r'^\s*- "([^"]*:81)"\s*$', sablon, re.M)
if yayinlar != ["{{ k_yonetim_bind }}:81:81"] or "{'agdan': '0.0.0.0', 'sunucu': '127.0.0.1'}[" not in read("roles/ortak/tasks/yazilim_koruma.yml"):
    err("proxy yönetim portu (81) yalnız IPv4 adresine bağlanmalı (0.0.0.0 ya da 127.0.0.1); otomatik karar IPv6'ya bakmaz")
if '"-4"' not in read("roles/proxy/files/yonetim_karari.py"):
    err("yonetim_karari.py yalnız IPv4 adreslerini okumalı (81 yalnız IPv4'te yayınlanır)")

# genel özet: yayımlanmış katalog kurulu ve portlar'ı buradan okur
for k in ["ana_durum", "docker", "kurulu", "portlar", "docker_servis"] + [f"{u}_kurulu" for u in uygulamalar]:
    if k not in keys_of("kurulum_durum"):
        err(f"eylem kurulum_durum: genel özet anahtarı '{k}' eksik")
# sonuç değeri 64 karakterde sessizce kesilir: liste değerlerinin EN UZUN hali sığmalı (native ve docker aynı uzunlukta; port en çok 5 hane)
SINIR = 64
en_uzun = {"kurulu": "+".join(f"{u}:docker" for u in uygulamalar if u not in ozet_disi),
           "portlar": "+".join(f"{u}:65535" for u in yazilimlar if u not in ozet_disi)}
for k, deger in en_uzun.items():
    if len(deger) > SINIR:
        err(f"kurulum_durum '{k}' en uzun halde {len(deger)} karakter (> {SINIR}): sonuç satırında sessizce kesilir; listenin biçimi değişmeli ({deger})")
    if not re.search(rf"^          {k}=\{{\{{ [^\n]*truncate\({SINIR}, True, ''\)", read("playbooks/kurulum_durum.yml"), re.M):
        err(f"playbooks/kurulum_durum.yml: '{k}' değeri {SINIR} karaktere sınırlanmalı")

if errors:
    print("TUTARSIZLIK:")
    for e in errors:
        print("  -", e)
    sys.exit(1)
print("OK: component.json, VERSION, CHANGELOG, README, profiller, değişkenler, sonuç satırları, uygulama okumaları ve kartlar tutarlı")
