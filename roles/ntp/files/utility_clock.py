#!/usr/bin/env python3
"""utility: chrony saat sapmasını ölçer ve gerekirse TEK SEFERLİK adımlar (hedef sunucuda çalışır; yalnızca standart kütüphane).

Girdi: tek bir JSON bağımsız değişkeni. Çıktı: stdout'a tek satır JSON.

  {"mode": "status", "threshold": 1.0}
      -> {"up": bool, "selected": bool, "drift_s": float|null, "source": "tracking"|"kaynak"|"yok", "sources": n, "reachable": n}
  {"mode": "step", "threshold": 1.0, "timeout": 60, "interval": 5}
      -> {"ok": bool, "stepped": bool, "initial_drift_s": float|null, "drift_s": float|null, "reason": "", "waited_s": n}

Sapma: seçili bir kaynak varsa `chronyc tracking` sistem saati farkı; yoksa erişilebilir (reach>0) kaynakların son örneklerinin
EN KÜÇÜK mutlak farkı (tek bir kötü kaynak adımlamaya yol açmasın). Ölçülemiyorsa null.
`step`: sapma eşikten büyükse `chronyc makestep` (kalıcı makestep ayarı YAZILMAZ); kaynaklar erişilebilir olana kadar bekler,
eşik altına inene ya da zaman aşımına kadar yineler. reason: chrony_yok | kaynak_yok (hiç ölçülemedi) | adimlanamadi (ölçüldü ama düzelmedi).
"""
import json
import subprocess
import sys
import time


def chronyc(*args):
    try:
        p = subprocess.run(["chronyc"] + list(args), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           universal_newlines=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return p.stdout if p.returncode == 0 else None


def status():
    out = chronyc("-c", "tracking")
    if not out or not out.strip():
        return {"up": False, "selected": False, "drift_s": None, "source": "yok", "sources": 0, "reachable": 0}
    f = out.strip().splitlines()[0].split(",")
    selected = False
    track = None
    try:
        selected = f[0].strip("0") != "" and int(f[2]) > 0
        track = abs(float(f[4]))
    except (IndexError, ValueError):
        pass
    lines = (chronyc("-c", "sources") or "").strip().splitlines()
    offs = []
    for ln in lines:
        g = ln.split(",")
        try:
            if int(g[5]) > 0:
                offs.append(abs(float(g[7])))
        except (IndexError, ValueError):
            continue
    if selected and track is not None:
        drift, src = track, "tracking"
    elif offs:
        drift, src = min(offs), "kaynak"
    else:
        drift, src = None, "yok"
    return {"up": True, "selected": selected, "drift_s": None if drift is None else round(drift, 3), "source": src,
            "sources": len(lines), "reachable": len(offs)}


def step(req):
    thr = float(req.get("threshold", 1.0))
    timeout = float(req.get("timeout", 60))
    interval = float(req.get("interval", 5))
    t0 = time.time()
    first = status()
    if not first["up"]:
        return {"ok": False, "stepped": False, "initial_drift_s": None, "drift_s": None, "reason": "chrony_yok", "waited_s": 0}
    stepped, last_step, cur = False, None, first
    while True:
        d = cur["drift_s"]
        if d is not None and d <= thr:
            return {"ok": True, "stepped": stepped, "initial_drift_s": first["drift_s"], "drift_s": d, "reason": "",
                    "waited_s": int(time.time() - t0)}
        if time.time() - t0 >= timeout:
            return {"ok": False, "stepped": stepped, "initial_drift_s": first["drift_s"], "drift_s": d,
                    "reason": "kaynak_yok" if d is None and not stepped else "adimlanamadi", "waited_s": int(time.time() - t0)}
        if d is not None and (last_step is None or time.time() - last_step >= interval):
            chronyc("makestep")
            stepped, last_step = True, time.time()
        time.sleep(min(interval, 2) if d is not None else interval)
        cur = status()
        if not cur["up"]:
            return {"ok": False, "stepped": stepped, "initial_drift_s": first["drift_s"], "drift_s": None, "reason": "chrony_yok",
                    "waited_s": int(time.time() - t0)}


def main(argv):
    if len(argv) != 1:
        print(json.dumps({"error": "tek JSON argümanı gerekir"}))
        return 2
    try:
        req = json.loads(argv[0])
        out = {"status": lambda r: status(), "step": step}[req["mode"]](req)
    except Exception as exc:  # noqa: BLE001 - tek satır JSON hata
        print(json.dumps({"error": "%s: %s" % (type(exc).__name__, exc)}))
        return 1
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
