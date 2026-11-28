#!/usr/bin/env python3
"""Nginx Proxy Manager yönetim ekranı için kurulum_proxy_yonetim=otomatik kararı. SALT OKUNUR: yalnız "ip -4 -o addr show" koşar.

Kullanım:  python3 -I - [JSON]      Çıktı: {"karar": "agdan|sunucu", "genel": ["<adres>", …] ya da null, "neden": "<düz metin>"}
  sunucu  herhangi bir arayüzde genel (internette yönlendirilebilir) IPv4 var, YA DA adresler okunamadı (güvenli yön)
  agdan   okunan IPv4 adreslerinin hepsi genel değil (özel, geri döngü, link-local, CGNAT, belge/ayrılmış aralıklar)
Yalnız IPv4'e bakılır: yönetim portu yalnız IPv4'te yayınlanır (compose: 0.0.0.0:81), genel IPv6 adresi onu açmaz.
SINIR: NAT arkasındaki sunucu (ör. bulut sağlayıcısının 1:1 NAT'ı) yalnız özel adres gösterir; internetten erişilebildiği buradan ANLAŞILMAZ.
"""
import ipaddress
import json
import os
import shutil
import subprocess
import sys

# PATH'te sbin olmayabilir
SBIN = "/usr/local/sbin:/usr/sbin:/sbin"


def adresler(ek_yol):
    """Arayüzlerdeki IPv4 adresleri; okunamadıysa ValueError."""
    yol = shutil.which("ip", path=os.environ.get("PATH", "") + os.pathsep + ek_yol)
    if yol is None:
        raise ValueError("ip komutu yok")
    try:
        r = subprocess.run([yol, "-4", "-o", "addr", "show"], capture_output=True, text=True, timeout=30, env=dict(os.environ, LC_ALL="C"))
    except (OSError, subprocess.SubprocessError) as e:
        raise ValueError(f"ip çalıştırılamadı: {type(e).__name__}") from e
    if r.returncode != 0:
        raise ValueError("ip hata verdi")
    sonuc = []
    for satir in r.stdout.splitlines():
        alan = satir.split()
        if not alan:
            continue
        # "2: eth0    inet 172.17.0.2/16 brd …"  (noktadan noktaya: "inet 10.0.0.1 peer 10.0.0.2/32")
        if "inet" not in alan or alan.index("inet") + 1 >= len(alan):
            raise ValueError("anlaşılmayan ip çıktısı")
        try:
            sonuc.append(ipaddress.IPv4Address(alan[alan.index("inet") + 1].split("/")[0]))
        except ValueError as e:
            raise ValueError("anlaşılmayan adres") from e
    # her sunucuda en az geri döngü adresi vardır: boş çıktı "adres yok" değil "okunamadı" demektir
    if not sonuc:
        raise ValueError("hiç adres okunamadı")
    return sonuc


def karar(ek_yol=SBIN):
    try:
        liste = adresler(ek_yol)
    except ValueError as e:
        return {"karar": "sunucu", "genel": None, "neden": f"sunucunun adresleri okunamadı ({e}); güvenli yön seçildi"}
    # is_global: özel, geri döngü, link-local, CGNAT (100.64.0.0/10), belge ve ayrılmış aralıklar genel sayılmaz; çok noktaya yayın da sayılmaz
    genel = [str(a) for a in liste if a.is_global and not a.is_multicast]
    if genel:
        return {"karar": "sunucu", "genel": genel, "neden": "sunucuda genel IPv4 adresi var: " + ", ".join(genel[:3])}
    return {"karar": "agdan", "genel": [], "neden": "sunucuda genel IPv4 adresi görünmüyor (NAT arkasındaki bulut sunucusu bu yolla algılanmaz)"}


if __name__ == "__main__":
    # ek_yol yalnız birim testleri içindir (playbook vermez)
    istek = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
    print(json.dumps(karar(istek.get("ek_yol", SBIN))))
