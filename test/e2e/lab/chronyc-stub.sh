#!/usr/bin/env bash
# LAB için SAHTE chronyc: konteynerde chronyd/saat adımlama yoktur. /run/utility-stub/{offset,reach,selected} durumunu okur;
# `makestep` (reach>0 ise) sapmayı kapatır ve /run/utility-stub/steps'e satır ekler. Yalnızca utility_clock.py mantığını sınar, chrony'yi DEĞİL.
S=/run/utility-stub
off=$(cat "$S/offset"); reach=$(cat "$S/reach"); sel=$(cat "$S/selected")
case "$*" in
  "-c tracking") if [ "$sel" = 1 ]; then echo "A9FE0101,x,3,0,$off,0,0,0,0,0,0,0,0"; else echo "00000000,,0,0,0,0,0,0,0,0,0,0,0"; fi ;;
  "-c sources") if [ "$sel" = 1 ]; then st='*'; else st='?'; fi; echo "^,$st,ntp.example,2,6,$reach,10,$off,0,0" ;;
  "makestep") if [ "$reach" != 0 ]; then echo 0.0002 > "$S/offset"; echo 1 > "$S/selected"; echo x >> "$S/steps"; fi ;;
  *) exit 1 ;;
esac
