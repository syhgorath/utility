# utility LAB hedefi: systemd + sshd + sudo + python3, DÜZ bir imaj (chrony ve locales BİLEREK yok: paket kurulum yolu denenir).
# Yalnızca yerel testler içindir; --privileged çalıştırılır ve Colima/Docker VM'inin çekirdeğini paylaşır.
ARG BASE=ubuntu:26.04
FROM ${BASE}
ENV DEBIAN_FRONTEND=noninteractive
# Paket listeleri BİLEREK silinmez: gerçek bir sunucuda da dururlar (aksi halde apt paketleri bulamaz).
RUN apt-get update \
 && apt-get install -y --no-install-recommends systemd systemd-sysv dbus openssh-server sudo python3 python3-apt \
        iproute2 procps ca-certificates tzdata \
 && apt-get update \
 && useradd -m -s /bin/bash tester \
 && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester && chmod 440 /etc/sudoers.d/tester \
 && mkdir -p /home/tester/.ssh && chmod 700 /home/tester/.ssh && chown tester:tester /home/tester/.ssh \
 && (systemctl enable ssh || systemctl enable sshd) \
 && systemctl set-default multi-user.target
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
