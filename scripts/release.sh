#!/usr/bin/env bash
# release.sh — Etiketli sürümden İMZALI paket üretir (bakımcı aracı, yerelde çalışır; CI'a ÖZEL ANAHTAR KONMAZ).
#
#   1) VERSION, component.json "version" ve CHANGELOG.md'yi güncelleyin; commit + etiket:  git tag -a vX.Y.Z -m "..."
#   2) PAKET_SIGNING_KEY=~/.ssh/<ozel_anahtar> scripts/release.sh
#   3) dist/<id>-<sürüm>.tar.gz ve .tar.gz.sig dosyalarını GitHub'da vX.Y.Z Release'ine yükleyin.
#   4) sshpocket reposuna kilit satırı ekleyen PR: scripts/lock-component.sh <id> <sürüm> --repo <sahip/depo> --write
#
# Güvenceler (yayından ÖNCE): temiz çalışma alanı, etiket = HEAD, CHANGELOG başlığı, tek kök dizin <id>-<sürüm>/, VERSION = component.json = etiket,
# geliştirme dosyası yok, sözleşme uyum denetimi (❌ varsa durur), imza yayından önce kendi public anahtarıyla doğrulanır.
set -euo pipefail
cd "$(dirname "$0")/.."

NS="sshpocket-component"                          # imza ad alanı; sshpocket doğrularken AYNISINI kullanır
SIGNER_ID="${PAKET_SIGNER_ID:-sshpocket-component}"
KEY="${PAKET_SIGNING_KEY:-$HOME/.ssh/sshpocket_release}"
die() { echo "HATA: $*" >&2; exit 1; }

command -v python3 >/dev/null || die "python3 yok"
command -v ssh-keygen >/dev/null || die "ssh-keygen yok"
ID=$(python3 -I -c 'import json; print(json.load(open("component.json"))["id"])')
JVER=$(python3 -I -c 'import json; print(json.load(open("component.json"))["version"])')
VERSION=$(tr -d '[:space:]' < VERSION)
[[ "$ID" =~ ^[a-z][a-z0-9-]*$ ]] || die "component.json id geçersiz: '$ID'"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION geçersiz: '$VERSION'"
[ "$JVER" = "$VERSION" ] || die "component.json sürümü ($JVER) VERSION ($VERSION) ile aynı değil"
TAG="v$VERSION"

[ -z "$(git status --porcelain)" ] || die "çalışma alanı temiz değil (commit edilmemiş değişiklik var)"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "etiket yok: $TAG (önce: git tag -a $TAG -m ...)"
[ "$(git rev-list -n1 "$TAG")" = "$(git rev-parse HEAD)" ] || die "$TAG şu anki commit'i göstermiyor"
grep -q "^## \[$VERSION\]" CHANGELOG.md || die "CHANGELOG.md içinde [$VERSION] başlığı yok"
[ -f "$KEY" ] || die "imza anahtarı bulunamadı: $KEY (PAKET_SIGNING_KEY ile belirtin)"

mkdir -p dist
ARCHIVE="dist/$ID-$VERSION.tar.gz"
rm -f "$ARCHIVE" "$ARCHIVE.sig"
git archive --format=tar.gz --prefix="$ID-$VERSION/" -o "$ARCHIVE" "$TAG"

roots=$(tar -tzf "$ARCHIVE" | cut -d/ -f1 | sort -u)
[ "$roots" = "$ID-$VERSION" ] || die "pakette beklenmeyen kök dizin(ler): $roots"
inner=$(tar -xzOf "$ARCHIVE" "$ID-$VERSION/VERSION" | tr -d '[:space:]')
[ "$inner" = "$VERSION" ] || die "paket içindeki VERSION ($inner) etiketle ($VERSION) aynı değil"
if tar -tzf "$ARCHIVE" | grep -qE "^$ID-$VERSION/(\.github/|tools/|scripts/|ornekler/|dist/|\.gitattributes)"; then
    die "pakette geliştirme dosyaları var (.gitattributes export-ignore kontrol edin)"
fi

# Sözleşme uyum denetimi (arşiv üzerinde; ❌ varsa imzalanmaz)
python3 -I tools/validate/component_validate.py "$ARCHIVE" --unsigned || die "sözleşme uyum denetimi başarısız (yukarıdaki ❌ satırlarına bakın)"

ssh-keygen -Y sign -f "$KEY" -n "$NS" "$ARCHIVE"

# Yayından önce kendi doğrulamamız (özel anahtardan türetilen public key, aynı principal/ad alanı)
PUB=$(ssh-keygen -y -f "$KEY" | cut -d' ' -f1,2)
SIGNERS=$(mktemp); trap 'rm -f "$SIGNERS"' EXIT
printf '%s namespaces="%s" %s\n' "$SIGNER_ID" "$NS" "$PUB" > "$SIGNERS"
ssh-keygen -Y verify -f "$SIGNERS" -I "$SIGNER_ID" -n "$NS" -s "$ARCHIVE.sig" < "$ARCHIVE" >/dev/null \
    || die "üretilen imza DOĞRULANAMADI (yanlış anahtar/principal/ad alanı?)"

echo "✅ $ARCHIVE ve $ARCHIVE.sig hazır"
echo "   Sonraki adım: dosyaları GitHub'da $TAG Release'ine yükleyin, sonra sshpocket'te scripts/lock-component.sh ile kilide yazın."
