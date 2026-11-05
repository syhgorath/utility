#!/usr/bin/env bash
# Hızlı testler (konteyner gerektirmez): test/*.sh, test/*.bats. LAB e2e ayrıdır: bats test/e2e/lab.bats
cd "$(dirname "$0")/.." || exit 1
rc=0
for t in test/test_*.sh; do echo "=== $t"; bash "$t" || rc=1; done
echo "=== test/backup.bats"; bats test/backup.bats || rc=1
echo "=== scripts/check-consistency.py"; python3 -I scripts/check-consistency.py || rc=1
exit $rc
