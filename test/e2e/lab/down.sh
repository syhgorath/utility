#!/usr/bin/env bash
# LAB konteynerini kaldırır. --clean: anahtarlar, host key (.state/) ve imajlar da silinir.
set -u
cd "$(dirname "$0")" || exit 1
docker rm -f utility-lab >/dev/null 2>&1 && echo "Konteyner kaldırıldı" || echo "Konteyner zaten yok"
if [ "${1:-}" = "--clean" ]; then
    rm -rf .state
    docker images --format '{{.Repository}}:{{.Tag}}' | grep '^utility-lab:' | xargs -r docker rmi >/dev/null 2>&1 || true
    echo ".state/ ve imajlar temizlendi"
fi
