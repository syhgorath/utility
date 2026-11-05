#!/usr/bin/env bash
# sync-validator.sh <sshpocket-dizini> — sshpocket'in paket sözleşme doğrulayıcısını tools/validate/ altına KOPYALAR (vendored) ve
# kaynağını + SHA-256'larını tools/validate/VENDORED.md'ye yazar. CI bu özetleri denetler (sessiz sapmayı yakalar).
# Neden kopya? CI ağdan betik indirip çalıştırmasın; çalıştırılan kod depoda görünür ve gözden geçirilebilir olsun.
set -euo pipefail
SRC="${1:?kullanım: tools/sync-validator.sh <sshpocket-dizini>}"
H="$SRC/sistem/Helpers"
for f in component_validate.py component_manifest.py; do [ -f "$H/$f" ] || { echo "bulunamadı: $H/$f" >&2; exit 1; }; done
[ -z "$(git -C "$SRC" status --porcelain -- sistem/Helpers/component_validate.py sistem/Helpers/component_manifest.py 2>/dev/null)" ] \
    || { echo "kaynakta commit edilmemiş değişiklik var; önce commit edin" >&2; exit 1; }
cd "$(dirname "$0")/validate"
cp "$H/component_validate.py" "$H/component_manifest.py" .
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }
{
    echo "# Vendored: sshpocket paket doğrulayıcısı"
    echo
    echo "Bu klasördeki dosyalar sshpocket'ten KOPYALANMIŞTIR; elle düzenlemeyin. Güncellemek için: \`tools/sync-validator.sh <sshpocket-dizini>\`."
    echo
    echo "- kaynak: https://github.com/syhgorath/sshpocket (commit \`$(git -C "$SRC" rev-parse --short HEAD)\`, sürüm \`$(tr -d '[:space:]' < "$SRC/VERSION")\`)"
    echo "- tarih: $(date -u +%Y-%m-%d)"
    echo
    echo "| dosya | sha256 |"
    echo "|---|---|"
    for f in component_validate.py component_manifest.py; do echo "| \`$f\` | \`$(sha "$f")\` |"; done
} > VENDORED.md
echo "✅ kopyalandı; özetler VENDORED.md içinde"
