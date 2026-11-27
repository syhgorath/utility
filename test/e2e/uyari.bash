# Temiz çıktı denetimi (LAB takımları ve test_static.sh alır): [WARNING] / [DEPRECATION WARNING] satırı olmamalı.
# TEK istisna, tam satır eşleşmesiyle: ssh pipelining açıkken, sunucuda root'un ansible geçici klasörü yokken ansible'ın bir kez bastığı satır (zararsız; README).
IZINLI_UYARI='[WARNING]: Module remote_tmp /root/.ansible/tmp did not exist and was created with a mode of 0700, this may cause issues when running as another user. To avoid this, create the remote_tmp dir with the correct permissions manually'
# beklenmeyen_uyarilar <günlük>: izinli satır dışındaki uyarıları satır numarasıyla yazar. Çıkış: 0 = var, 1 = yok, 2 = günlük okunamadı.
beklenmeyen_uyarilar() {
  awk -v izinli="$IZINLI_UYARI" '$0 != izinli && /\[(DEPRECATION )?WARNING\]/ { print NR ":" $0; n++ } END { exit !n }' "$1"
}
