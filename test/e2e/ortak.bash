# LAB e2e ortak yardımcılar (bats dosyaları load ile alır).
. "$BATS_TEST_DIRNAME/uyari.bash"
RUN="$BATS_TEST_DIRNAME/lab/run.sh"
lab() { docker exec kurulum-lab "$@"; }
result() { grep -o 'SSHPOCKET_RESULT utility\.[a-z_]* .*' <<<"$output" | tail -n1 | sed 's/"$//'; }
recap_changed() { grep -E '^lab +:' <<<"$output" | sed -E 's/.*changed=([0-9]+).*/\1/'; }
recap_failed() { grep -E '^lab +:' <<<"$output" | sed -E 's/.*failed=([0-9]+).*/\1/'; }
# her koşunun ekranı toplanır (parola sızıntı testi için); run sonrası çağrılır
logla() { printf '%s\n' "$output" >> "$BATS_FILE_TMPDIR/hepsi.log"; }
krun() { run "$RUN" "$@"; logla; }
