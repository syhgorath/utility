#!/usr/bin/env bash
# Hızlı testler: test/test_*.sh (statik denetim parmak izi için docker varsa kullanır), test/*.bats. LAB e2e ayrıdır: bats test/e2e/lab-docker.bats test/e2e/lab-native.bats test/e2e/lab-preview.bats test/e2e/lab-apt.bats test/e2e/lab-duvar.bats test/e2e/lab-proxy.bats test/e2e/lab-redisui.bats test/e2e/lab-utility.bats
cd "$(dirname "$0")/.." || exit 1
rc=0
for t in test/test_*.sh; do echo "=== $t"; bash "$t" || rc=1; done
echo "=== test/backup.bats test/clock.bats test/duvar.bats test/proxy_yonetim.bats"; bats test/backup.bats test/clock.bats test/duvar.bats test/proxy_yonetim.bats || rc=1
echo "=== scripts/check-consistency.py"; python3 -I scripts/check-consistency.py || rc=1
exit $rc
