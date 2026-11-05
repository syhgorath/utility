# Gerçek VM turu (kullanıcı yapar)

> Bu tur henüz **yapılmadı**. Her satırı sonuç günlüğüne yazın (`seçenek | platform | durum | not`); denenmeyen satırı "denendi" yazmayın.
> Önce her VM'de **snapshot alın**. Komutlar sshpocket menüsü yerine doğrudan playbook ile de çalışır (aşağıda); menü turu kilit PR'ından sonradır.

## Hazırlık
- Kontrol makinesi: `~/Developer/utility` (venv: `python3.13 -m venv .venv && .venv/bin/pip install --require-hashes --only-binary :all: -r requirements.txt`).
- Sunucu girişi: `ubuntutest` IP'si DHCP ile .183/.186/.188 arasında gezer (`server.env`'e bakın); Debian 13 için **düz bir VM** gerekir.
- Envanter dosyası (örnek; IP/kullanıcıyı kendinize göre yazın):
```bash
printf 'utility:\n  hosts:\n    vm:\n      ansible_host: 192.168.1.183\n      ansible_user: KULLANICI\n' > /tmp/utility-inv.yml
printf '{"utility_timezone":"Europe/Istanbul","utility_locale":"en_US.UTF-8","utility_ntp_servers":["pool 2.pool.ntp.org"]}' > /tmp/utility-vars.json
```
(`/tmp` yerine bir klasör seçebilirsiniz; dosyalarda gizli değer yoktur.)

## Sıra
```bash
cd ~/Developer/utility
.venv/bin/ansible-playbook -i /tmp/utility-inv.yml playbooks/durum.yml
.venv/bin/ansible-playbook -i /tmp/utility-inv.yml playbooks/preview.yml --check --diff -e @/tmp/utility-vars.json --ask-become-pass
```
Snapshot teyidinden sonra:
```bash
.venv/bin/ansible-playbook -i /tmp/utility-inv.yml playbooks/apply.yml -e @/tmp/utility-vars.json --ask-become-pass
```
Bağımsız salt okunur doğrulama (ayrı bir ssh oturumundan):
```bash
ssh KULLANICI@IP 'timedatectl; grep ^LANG= /etc/default/locale; cat /etc/chrony/sources.d/utility.sources; chronyc sources; sudo ls -l /var/backups/utility/*/'
```
İkinci önizleme (`degisen=0` ve `changed=0` beklenir), sonra geri yükleme:
```bash
.venv/bin/ansible-playbook -i /tmp/utility-inv.yml playbooks/preview.yml --check --diff -e @/tmp/utility-vars.json --ask-become-pass
.venv/bin/ansible-playbook -i /tmp/utility-inv.yml playbooks/geri_yukle.yml --ask-become-pass
```
(Menüden değil doğrudan çalıştırıldığı için sshpocket'in onay/ön koşul kapıları yoktur.)

## Debian 13'te özellikle bakılacaklar (doğrulanana kadar `planned`)
- `apt` ile chrony kurulumu `systemd-timesyncd`'yi kaldırıyor/devre dışı bırakıyor mu? (`systemctl status systemd-timesyncd chrony` önce/sonra)
- `/etc/chrony/chrony.conf` içinde `sourcedir /etc/chrony/sources.d` var mı? (yoksa apply bilerek durur)
- `chronyc sources` utility kaynağını gösteriyor mu; `timedatectl show -p NTPSynchronized` `yes` oluyor mu?

## Ardından: linux-hardening uygulanmış VM'de birlikte
Aynı sıra; ek olarak `sudo ausearch -k time-change` (saat dilimi değişince kayıt beklenir) ve ufw giden trafik reddi açıkken 123/udp (ve Ubuntu varsayılan NTS kaynakları için 4460/tcp) davranışı not edilir.
