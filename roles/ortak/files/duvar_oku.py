#!/usr/bin/env python3
"""Yönetilen uygulama portunun güvenlik duvarı (ufw) durumu. SALT OKUNUR: yalnız aşağıdaki okuma komutları koşar, hiçbir şey yazmaz.

Kullanım:  python3 -I - '{"mod": "native", "erisim": "agdan", "port": "8080"}'     Çıktı: {"duvar": "<değer>", "neden": "<düz metin>"}
  acik        ufw yok/kapalı ya da porta her yerden izin var
  kisitli     porta yalnız bazı kaynaklardan/adreslerden/arayüzlerden erişilir
  engelliyor  ufw açık ve porta dışarıdan izin yok (native)
  atlanir     docker portu ağa yayınlı: ufw bu porta uygulanmaz
  gerekmez    port ağa açık değil (kurulu değil ya da erişim ic/sunucu)
  unknown     okunamadı ya da bu okumanın anlamadığı bir yapılandırma var: tahmin edilmez
Yalnız ufw'nin kullanıcı kuralları (IPv4, user.rules) ve gelen varsayılanı değerlendirilir. before.rules'a elle eklenenler, sunucu dışındaki
güvenlik duvarları (bulut sağlayıcısı, yönlendirici) ve ufw dışı elle yazılmış iptables/nftables kuralları OKUNMAZ.
"""
import json
import os
import re
import shutil
import subprocess
import sys

HERKES = ("0.0.0.0/0",)


class Okunamadi(Exception):
    pass


# PATH'te sbin olmayabilir: ufw bulunamazsa yanlışlıkla "kurulu değil" denmesin
SBIN = "/usr/local/sbin:/usr/sbin:/sbin"


def komut(argv, ek_yol):
    """(rc, stdout); komut yoksa None."""
    yol = shutil.which(argv[0], path=os.environ.get("PATH", "") + os.pathsep + ek_yol)
    if yol is None:
        return None
    try:
        r = subprocess.run([yol] + argv[1:], capture_output=True, text=True, timeout=30, env=dict(os.environ, LC_ALL="C", LANGUAGE="C"))
    except (OSError, subprocess.SubprocessError) as e:
        raise Okunamadi(f"{argv[0]} çalıştırılamadı: {type(e).__name__}") from e
    return r.returncode, r.stdout


def dosya(root, yol):
    """Dosya içeriği; dosya yoksa None."""
    try:
        with open(os.path.join(root, yol.lstrip("/")), encoding="utf-8", errors="replace") as f:
            return f.read()
    except FileNotFoundError:
        return None
    except OSError as e:
        raise Okunamadi(f"{yol} okunamadı") from e


def port_uyar(ifade, port):
    """ufw port ifadesi ('any', '80', '80,443', '8000:8010') portu kapsıyor mu."""
    if ifade == "any":
        return True
    for parca in ifade.split(","):
        m = re.fullmatch(r"(\d+)(?::(\d+))?", parca)
        if not m:
            raise Okunamadi(f"anlaşılmayan ufw port ifadesi: {parca}")
        if int(m.group(1)) <= port <= int(m.group(2) or m.group(1)):
            return True
    return False


def kurallar(metin, port):
    """user.rules '### tuple ###' satırlarından porta gelen trafiği etkileyenler, sırasıyla: (izin mi, herkes mi)."""
    for satir in metin.splitlines():
        if not satir.startswith("### tuple ###"):
            continue
        alan = [a for a in satir.split()[3:] if not a.startswith("comment=")]
        if alan and alan[0].startswith("route:"):
            continue  # yönlendirilen trafik: sunucunun kendi portunu etkilemez
        # eylem proto dport dst sport src [dapp sapp] [yön]
        yon = alan.pop() if alan and re.fullmatch(r"(in|out)(_\S+)?(![a-z]+_\S+)?", alan[-1]) else "in"
        if len(alan) not in (6, 8):
            raise Okunamadi("anlaşılmayan ufw kural satırı")
        eylem, proto, dport, dst, sport, src = alan[:6]
        eylem = eylem.split("_")[0]  # allow_log, deny_log-all
        if eylem not in ("allow", "limit", "deny", "reject"):
            raise Okunamadi(f"anlaşılmayan ufw eylemi: {eylem}")
        # giden ve geri döngü (lo) kuralları dışarıdan erişimi etkilemez
        if yon.startswith("out") or yon == "in_lo" or proto not in ("tcp", "any") or not port_uyar(dport, port):
            continue
        herkes = yon == "in" and dst in HERKES and src in HERKES and sport == "any"
        yield eylem in ("allow", "limit"), herkes


def ufw_karari(durum, kural_metni, port):
    m = re.search(r"^Default:\s*(allow|deny|reject)\s*\(incoming\)", durum, re.M)
    if not m:
        raise Okunamadi("ufw gelen trafik varsayılanı okunamadı")
    varsayilan_izin = m.group(1) == "allow"
    kismi_izin = kismi_ret = False
    for izin, herkes in kurallar(kural_metni, port):
        if not herkes:
            kismi_izin, kismi_ret = kismi_izin or izin, kismi_ret or not izin
            continue
        # herkesi kapsayan ilk kural sonucu belirler (ufw: ilk eşleşen kazanır); önündeki kısmi kurallar istisnadır
        if izin:
            return ("kisitli", "bazı kaynaklar reddediliyor") if kismi_ret else ("acik", f"{port}/tcp için herkese izin kuralı var")
        return ("kisitli", "yalnız bazı kaynaklara izin var") if kismi_izin else ("engelliyor", f"{port}/tcp herkese reddediliyor")
    if varsayilan_izin:
        return ("kisitli", "bazı kaynaklar reddediliyor") if kismi_ret else ("acik", "ufw gelen trafiğe varsayılan olarak izin veriyor")
    if kismi_izin:
        return "kisitli", f"{port}/tcp için yalnız bazı kaynaklardan/adreslerden/arayüzlerden izin var"
    return "engelliyor", f"ufw açık, gelen trafik varsayılan olarak reddediliyor ve {port}/tcp için izin kuralı yok"


def docker_karari(root, ek_yol):
    """Docker yayını ufw'yi atlar; bunu bozabilen iki yapılandırmada iddiada bulunulmaz."""
    ayar = dosya(root, "/etc/docker/daemon.json")
    if ayar is not None and ayar.strip():
        try:
            veri = json.loads(ayar)
            iptables = veri.get("iptables", True)
        except (ValueError, AttributeError) as e:
            raise Okunamadi("/etc/docker/daemon.json çözülemedi") from e
        if iptables is not True:
            raise Okunamadi("docker iptables yönetimi kapalı (daemon.json)")
    r = komut(["iptables", "-S", "DOCKER-USER"], ek_yol)
    if r is None or r[0] != 0:
        raise Okunamadi("DOCKER-USER zinciri okunamadı")
    ek = [s for s in r[1].splitlines() if s.startswith("-A ") and s.split() != ["-A", "DOCKER-USER", "-j", "RETURN"]]
    if ek:
        raise Okunamadi("DOCKER-USER zincirinde ek kural var: etkisi değerlendirilmez")
    return "atlanir", "docker yayınladığı portu ufw kurallarından geçirmez"


def native_karari(root, port, ek_yol):
    r = komut(["ufw", "status", "verbose"], ek_yol)
    if r is not None:
        if r[0] != 0:
            raise Okunamadi("ufw durumu okunamadı")
        if re.search(r"^Status:\s*active\s*$", r[1], re.M):
            metin = dosya(root, "/etc/ufw/user.rules")
            if metin is None:
                raise Okunamadi("/etc/ufw/user.rules yok")
            return ufw_karari(r[1], metin, port)
        if not re.search(r"^Status:\s*inactive\s*$", r[1], re.M):
            raise Okunamadi("ufw durumu anlaşılamadı")
    # ufw yok ya da kapalı: başka bir güvenlik duvarı servisi çalışıyorsa "açık" denemez
    for servis in ("firewalld", "nftables"):
        s = komut(["systemctl", "is-active", servis], ek_yol)
        if s is None:
            raise Okunamadi("systemctl yok")
        if s[1].strip() == "active":
            raise Okunamadi(f"ufw yok/kapalı ama {servis} çalışıyor")
    return "acik", "ufw kurulu değil" if r is None else "ufw kapalı"


def karar(istek):
    erisim, mod, port = istek.get("erisim"), istek.get("mod"), str(istek.get("port"))
    if erisim in ("yok", "ic", "sunucu"):
        return "gerekmez", "port ağa açık değil"
    if erisim != "agdan":
        return "unknown", "ağ erişimi okunamadı"
    if not port.isdigit() or not 0 < int(port) < 65536:
        return "unknown", "port okunamadı"
    # root ve ek_yol yalnız birim testleri içindir (playbook vermez)
    root, ek_yol = istek.get("root", "/"), istek.get("ek_yol", SBIN)
    try:
        if mod == "docker":
            return docker_karari(root, ek_yol)
        if mod == "native":
            return native_karari(root, int(port), ek_yol)
    except Okunamadi as e:
        return "unknown", str(e)
    return "unknown", "kurulum modu bilinmiyor"


if __name__ == "__main__":
    d, n = karar(json.loads(sys.argv[1]))
    print(json.dumps({"duvar": d, "neden": n}))
