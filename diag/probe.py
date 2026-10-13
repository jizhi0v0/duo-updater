# THROWAWAY: hold one image attached (volume unmounted) and poll `hdiutil info -plist`
# until <stopfile> exists. After every listing that leaves it out, read 5 more at once.
import subprocess, plistlib, sys, os, time
base, stopfile, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(os.path.join(base, "src"), exist_ok=True)
open(os.path.join(base, "src", "p"), "w").write("x")
img = os.path.join(base, "probe.dmg"); mnt = os.path.join(base, "mnt"); os.makedirs(mnt, exist_ok=True)
subprocess.run(["hdiutil", "makehybrid", "-quiet", "-hfs", "-hfs-volume-name", "ZZProbe", "-o", img, os.path.join(base, "src")], check=True)
for attempt in range(10):
    if subprocess.run(["hdiutil", "attach", img, "-nobrowse", "-readonly", "-noverify", "-mountpoint", mnt], capture_output=True).returncode == 0: break
    time.sleep(2)
subprocess.run(["diskutil", "unmount", mnt], capture_output=True)
want = os.path.realpath(img)
def read():
    r = subprocess.run(["hdiutil", "info", "-plist"], capture_output=True)
    try: paths = [os.path.realpath(i.get("image-path", "")) for i in plistlib.loads(r.stdout).get("images", [])]
    except Exception: return None, r
    return want in paths, r
log = open(out, "a"); total = misses = 0; worst_run = 0
while not os.path.exists(stopfile):
    ok, r = read(); total += 1
    if ok is None: log.write(f"UNPARSEABLE rc={r.returncode}\n"); continue
    if ok: continue
    misses += 1
    again = [read()[0] for _ in range(5)]
    run = 1
    for a in again:
        if a: break
        run += 1
    worst_run = max(worst_run, run)
    log.write(f"MISS {time.strftime('%H:%M:%S')} rc={r.returncode} bytes={len(r.stdout)} err={r.stderr.decode()[:150]!r} rereads={again}\n"); log.flush()
log.write(f"TOTAL reads={total} misses={misses} longest_run_of_misses={worst_run}\n"); log.close()
