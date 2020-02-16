#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

if $BOARD == "orangepipcplus"
then
  # Downgrade kernel to 4.14 because 4.19 is causing issues with Wifi drivers so far
  apt install linux-image-next-sunxi=5.67 -y --allow-downgrades || exit -1
  apt-mark hold linux-image-next-sunxi
fi

# We don't want the damn network-manager :/
apt remove network-manager -y || true
apt autoremove -y
cat << EOF >> /etc/apt/preferences
Package: network-manager
Pin: release *
Pin-Priority: -1
EOF
echo "auto eth0" > /etc/network/interfaces.d/eth0.conf
echo "allow-hotplug eth0" >> /etc/network/interfaces.d/eth0.conf
echo "iface eth0 inet dhcp" >> /etc/network/interfaces.d/eth0.conf
echo " post-up ip a a fe80::42:acab/128 dev eth0" >> /etc/network/interfaces.d/eth0.conf

# Disable those damn supposedly "predictive" interface names
# c.f. https://unix.stackexchange.com/a/338730
ln -s /dev/null /etc/systemd/network/99-default.link

# Prevent dhcp setting the "search" thing in /etc/resolv.conf, leads to many
# weird stuff (e.g. with numericable) where any domain will ping >.>
echo 'supersede domain-name "";'   >> /etc/dhcp/dhclient.conf
echo 'supersede domain-search "";' >> /etc/dhcp/dhclient.conf
echo 'supersede search "";       ' >> /etc/dhcp/dhclient.conf

# Backports are evil
sed -i '/backport/ s/^deb/#deb/' /etc/apt/sources.list

# Avahi and mysql/mariadb needs to do some stuff which conflicts with
# the "change the root password asap" so we disable it. In fact, now
# that YunoHost 3.3 syncs the password with admin password at
# postinstall we are happy with not triggering a password change at
# first boot.  Assuming that ARM-boards won't be exposed to global
# network right after booting the first time ...
chage -d 99999999 root

# Run the install script
curl https://install.yunohost.org/stretch | bash -s -- -a
rm /var/log/yunohost-installation*

# Install InternetCube dependencies usb detection, hotspot, vpnclient, roundcube
apt-get install -o Dpkg::Options::='--force-confold' -y --force-yes \
  file udisks2 udiskie ntfs-3g jq \
  php7.0-fpm sipcalc hostapd iptables iw dnsmasq firmware-linux-free \
  sipcalc dnsutils openvpn curl fake-hwclock \
  php-cli php-common php-intl php-json php-mcrypt php-pear php-auth-sasl php-mail-mime php-patchwork-utf8 php-net-smtp php-net-socket php-net-ldap2 php-net-ldap3 php-zip php-gd php-mbstring php-curl

# Override the first login script with our own (we don't care about desktop
# stuff + we don't want the user to manually create a user)
cp /tmp/overlay/check_yunohost_is_installed.sh /etc/profile.d/check_yunohost_is_installed.sh
dpkg-divert --divert /root/armbian-check-first-login.sh --rename /etc/profile.d/armbian-check-first-login.sh
dpkg-divert --divert /root/armbian-motd --rename /etc/default/armbian-motd
rm -f /etc/profile.d/armbian-check-first-login.sh
cp /tmp/overlay/check_first_login.sh /etc/profile.d/check_first_login.sh
cp /tmp/overlay/armbian-motd /etc/default/armbian-motd
touch /root/.not_logged_in_yet

# Make sure resolv.conf points to DNSmasq
# (somehow networkmanager or something else breaks this before...)
rm -f /etc/resolv.conf
ln -s /etc/resolvconf/run/resolv.conf /etc/resolv.conf

# Clean stuff
apt clean
