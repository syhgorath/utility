#!/usr/bin/env python3
"""utility: yedekleme ve geri yükleme (hedef sunucuda çalışır; yalnızca standart kütüphane).

Girdi: tek bir JSON bağımsız değişkeni (ansible.builtin.script `cmd:` ile). Çıktı: stdout'a tek satır JSON.

  {"mode": "backup",  "dir": "/var/backups/utility", "paths": ["/etc/localtime", ...]}      # yedek adı = UTC zaman damgası (betik üretir)
  {"mode": "restore", "dir": "/var/backups/utility", "from": "", "dry_run": false}      # from boş = en son yedek

Yedek:  <dir>/<stamp>/        (0700)
          manifest.json       (0600)  her yol için: durum (absent/file/symlink), mod, uid/gid, bağ hedefi, sha256, saklanan dosya
          files/<n>           (0600)  dosya içerikleri
Geri yükleme YALNIZ aşağıdaki katalogdaki yollara yazar (kurcalanmış bir manifest başka yola yazdıramasın); katalog dışı yol atlanır ve sayılır.
`root` (yalnız testler): tüm mutlak yolların önüne eklenen dizin. Gerçek koşuda verilmez.
"""
import hashlib
import json
import os
import re
import shutil
import sys
import time

CATALOG_EXACT = ("/etc/localtime", "/etc/timezone", "/etc/default/locale", "/etc/locale.conf", "/etc/locale.gen")
CATALOG_DIRS = ("/etc/chrony/conf.d/", "/etc/chrony/sources.d/")
STAMP_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z(-[0-9]{1,3})?$")


def in_catalog(path):
    if not path.startswith("/") or ".." in path.split("/") or "\0" in path:
        return False
    if path in CATALOG_EXACT:
        return True
    return any(path.startswith(d) and "/" not in path[len(d):] and len(path) > len(d) for d in CATALOG_DIRS)


def real(root, path):
    return os.path.join(root, path.lstrip("/")) if root else path


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def backup(req):
    root = req.get("root", "")
    base = real(root, req["dir"])
    paths = req["paths"]
    stamp = req.get("stamp") or time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())   # UTC; "stamp" yalnız testler için
    if not STAMP_RE.match(stamp):
        raise ValueError("stamp biçimi geçersiz")
    bad = [p for p in paths if not in_catalog(p)]
    if bad:
        raise ValueError("katalog dışı yol: " + ",".join(bad))
    os.makedirs(base, mode=0o700, exist_ok=True)
    os.chmod(base, 0o700)
    dest, n = os.path.join(base, stamp), 0
    while True:
        try:
            os.mkdir(dest, 0o700)
            break
        except FileExistsError:
            n += 1
            dest = os.path.join(base, "%s-%d" % (stamp, n))
    os.mkdir(os.path.join(dest, "files"), 0o700)
    entries = []
    for i, p in enumerate(paths):
        rp = real(root, p)
        if os.path.islink(rp):
            st = os.lstat(rp)
            entries.append({"path": p, "state": "symlink", "link": os.readlink(rp), "uid": st.st_uid, "gid": st.st_gid})
        elif os.path.isfile(rp):
            st = os.stat(rp)
            stored = "files/%d" % i
            sp = os.path.join(dest, stored)
            fd = os.open(sp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            os.close(fd)
            shutil.copyfile(rp, sp)
            os.chmod(sp, 0o600)
            entries.append({"path": p, "state": "file", "mode": st.st_mode & 0o7777, "uid": st.st_uid, "gid": st.st_gid,
                            "sha256": sha256(sp), "stored": stored})
        elif not os.path.lexists(rp):
            entries.append({"path": p, "state": "absent"})
        else:
            raise ValueError("desteklenmeyen dosya türü: " + p)
    mp = os.path.join(dest, "manifest.json")
    fd = os.open(mp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump({"version": 1, "stamp": os.path.basename(dest), "entries": entries}, f, indent=2)
        f.write("\n")
    return {"dir": dest, "saved": len(entries)}


def latest(base):
    names = [n for n in os.listdir(base) if STAMP_RE.match(n) and os.path.isfile(os.path.join(base, n, "manifest.json"))]
    # "<stamp>-<n>" aynı saniyedeki sonraki yedektir: (zaman, n) sırası
    def key(n):
        s, _, k = n.partition("-")
        return (s, int(k or 0))
    return max(names, key=key) if names else None


def restore(req):
    root = req.get("root", "")
    base = real(root, req["dir"])
    want = req.get("from") or ""
    if want and not STAMP_RE.match(want):
        raise ValueError("from biçimi geçersiz")
    if not os.path.isdir(base):
        raise ValueError("yedek dizini yok: " + req["dir"])
    name = want or latest(base)
    if not name:
        raise ValueError("geri yüklenecek yedek yok")
    src = os.path.join(base, name)
    with open(os.path.join(src, "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    dry = bool(req.get("dry_run"))
    restored, skipped, changed_paths = 0, 0, []
    for e in manifest["entries"]:
        p = e["path"]
        if not in_catalog(p):
            skipped += 1
            continue
        rp = real(root, p)
        st = e["state"]
        if st == "absent":
            if os.path.lexists(rp):
                changed_paths.append(p)
                if not dry:
                    os.unlink(rp)
            restored += 1
            continue
        if st == "symlink":
            same = os.path.islink(rp) and os.readlink(rp) == e["link"]
            if not same:
                changed_paths.append(p)
                if not dry:
                    if os.path.lexists(rp):
                        os.unlink(rp)
                    os.makedirs(os.path.dirname(rp), exist_ok=True)
                    os.symlink(e["link"], rp)
            restored += 1
            continue
        if st == "file":
            sp = os.path.join(src, e["stored"])
            if sha256(sp) != e["sha256"]:
                raise ValueError("yedek bozuk (özet uyuşmuyor): " + p)
            same = (os.path.isfile(rp) and not os.path.islink(rp) and sha256(rp) == e["sha256"]
                    and (os.stat(rp).st_mode & 0o7777) == e["mode"])
            if not same:
                changed_paths.append(p)
                if not dry:
                    if os.path.lexists(rp):
                        os.unlink(rp)
                    os.makedirs(os.path.dirname(rp), exist_ok=True)
                    tmp = rp + ".utility-tmp"
                    shutil.copyfile(sp, tmp)
                    os.chmod(tmp, e["mode"])
                    try:
                        os.chown(tmp, e["uid"], e["gid"])
                    except PermissionError:
                        pass
                    os.replace(tmp, rp)
            restored += 1
            continue
        skipped += 1
    return {"from": name, "restored": restored, "changed": len(changed_paths), "changed_paths": changed_paths, "skipped": skipped}


def main(argv):
    if len(argv) != 1:
        print(json.dumps({"error": "tek JSON argümanı gerekir"}))
        return 2
    try:
        req = json.loads(argv[0])
        out = {"backup": backup, "restore": restore}[req["mode"]](req)
    except Exception as exc:  # noqa: BLE001 - tek satır JSON hata; Ansible görevi failed_when ile düşürür
        print(json.dumps({"error": "%s: %s" % (type(exc).__name__, exc)}))
        return 1
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
