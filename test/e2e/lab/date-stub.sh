#!/usr/bin/env bash
# LAB için SAHTE date: konteynerde saat ayarlanamaz. /run/utility-stub/skew (sn) kadar kaydırılmış epoch verir; `-s @N` kaymayı sıfırlar ve datesets'e yazar.
# Yalnızca utility'nin kontrolcü-karşılaştırma ve `date -s` akışını sınar. Gerçek saat adımlamayı DEĞİL.
S=/run/utility-stub; skew=$(cat "$S/skew" 2>/dev/null || echo 0)
case "$*" in
  "+%s") echo $(( $(/bin/date +%s) + skew )) ;;
  "-u -s @"*) echo "$*" >> "$S/datesets"; echo 0 > "$S/skew" ;;
  *) exec /bin/date "$@" ;;
esac
