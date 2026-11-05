#!/usr/bin/env python3
"""component.json, VERSION, CHANGELOG, README profil tablosu ve playbook/rol değişken kullanımı arasındaki tutarlılığı denetler.

Kullanım (repo kökünde):  python3 -I scripts/check-consistency.py        (yalnızca standart kütüphane)
Hata varsa çıkış kodu 1. linux-hardening/scripts/check-consistency.py'nin utility'ye uyarlanmış, çok daha küçük karşılığıdır.

Kurallar:
  - VERSION = component.json version; CHANGELOG.md'de '## [<sürüm>]' başlığı var.
  - Profil eşlemesi: component.json'daki supported profiller roles/common/defaults'taki utility_supported_os ile,
    planned profiller utility_planned_os ile BİREBİR aynı olmalı (Debian 13 planned iken supported listede olamaz).
  - README.md her profil için bir satır içerir.
  - component.json'daki her değişken, bir rolün defaults'ında tanımlıdır ve türü/varsayılanı uyuşur.
  - Her eylemin sonuç anahtarları, playbook'taki SSHPOCKET_RESULT satırında yazılır.
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
defaults = read("roles/common/defaults/main.yml")


def os_map(name):
    m = re.search(rf"^{name}:\s*\{{(.*)\}}", defaults, re.M)
    if not m:
        err(f"roles/common/defaults/main.yml içinde {name} yok")
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
    if f"SSHPOCKET_RESULT utility.{name}" not in text:
        err(f"eylem {name}: playbook 'SSHPOCKET_RESULT utility.{name}' satırını yazmıyor")

if errors:
    print("TUTARSIZLIK:")
    for e in errors:
        print("  -", e)
    sys.exit(1)
print("OK: component.json, VERSION, CHANGELOG, README, profiller, değişkenler, sonuç satırları tutarlı")
