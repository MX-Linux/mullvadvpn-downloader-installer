#!/bin/bash

# mullvadvpn 64bit only
#
[ "$(dpkg --print-architecture)" = "amd64" ] || exit 1

###########################################
# prepare tidy-up
tidy_up() {
	# tidy up
	[ "$SYSTEMCTL_EXIST" = "false" ] &&  rm /bin/systemctl 2>/dev/null
	rm -r /tmp/mullvad-keyring 2>/dev/null
	rm /tmp/mullvadvpn-linux.deb 2>/dev/null
	rm /tmp/mullvadvpn-linux.deb.asc 2>/dev/null
}
trap tidy_up EXIT

DEB=$(curl -L -s --head https://mullvad.net/download/latest-deb-app 2>/dev/null | grep location | tail -1) 
DEB="${DEB##*/}"
[ -n "${DEB##*.deb}" -o -n "${DEB%%MullvadVPN*}" ] && DEB="MullvadVPN-latest.deb"

# get mullvadvpn
#
echo "Downloading Mullvad VPN for Linux 64bit : ${DEB}"

[ -n "$DEB" ] || { echo "ERROR: Download of Mullvad VPN failed [no package name] "; exit 3; } 

rm /tmp/mullvadvpn-linux.deb 2>/dev/null

#wget -O /tmp/mullvad-linux.deb --trust-server-names https://mullvad.net/download/latest-deb-app
curl -RL -o /tmp/mullvad-linux.deb https://mullvad.net/download/latest-deb-app

[ -f /tmp/mullvad-linux.deb ] || { echo "ERROR: Download of '${DEB}' failed "; exit 3; }


# get signature
#
echo "Downloading Mullvad VPN signature : ${FLN##*/}.asc"
rm /tmp/mullvadvpn-linux.deb.asc 2>/dev/null
#wget -O /tmp/mullvad-linux.deb.asc --trust-server-names https://mullvad.net/download/latest-deb-sig

curl -RL -o /tmp/mullvad-linux.deb.asc https://mullvad.net/download/latest-deb-sig 
[ -f /tmp/mullvad-linux.deb.asc ] || { echo "ERROR: Download of signature '${DEB}.asc' failed "; exit 4; }

rm -r /tmp/mullvad-keyring 2>/dev/null
mkdir /tmp/mullvad-keyring
chmod 700 /tmp/mullvad-keyring

# get Mullvad signing key
#
echo "Downloading Mullvad VPN signing key : mullvad-code-signing.asc"

curl -RL https://mullvad.net/media/mullvad-code-signing.asc \
     -o /tmp/mullvad-keyring/mullvad-code-signing.asc
[ -f /tmp/mullvad-keyring/mullvad-code-signing.asc ] || { 
    echo "ERROR: Download of Mullvad VPN signing key : mullvad-code-signing.asc failed "; exit 5; }

# import signing key into temp keyring 

echo "Create Mullvad Keyring"
gpg --no-default-keyring --homedir=/tmp/mullvad-keyring \
    --keyring /tmp/mullvad-keyring/mullvad-temp.kbx \
    --import /tmp/mullvad-keyring/mullvad-code-signing.asc 2>/dev/null

# gpg sanity 
#
# Mullvad public signing key
KEY=A1198702FC3E0A09A9AE5B75D5A1D4F266DE8DDF
gpg --output  /tmp/mullvad-keyring/$KEY.gpg --no-default-keyring \
    --homedir=/tmp/mullvad-keyring \
    --keyring /tmp/mullvad-keyring/mullvad-temp.kbx \
    --export $KEY 2>/dev/null

[ -f /tmp/mullvad-keyring/$KEY.gpg ] || { 
    echo "ERROR: Mullvad VPN signing key sanity check failed: missing signing key $KEY "; exit 5; }

# remove temp keyring 
rm /tmp/mullvad-keyring/mullvad-temp.kbx 

# import signing key into mullvad keyring 
gpg --no-default-keyring --homedir=/tmp/mullvad-keyring \
    --keyring /tmp/mullvad-keyring/mullvad-keyring.kbx \
    --import /tmp/mullvad-keyring/$KEY.gpg 2>/dev/null

# Show Mullvad Signing key:
echo "Mullvad signing key used to verify:"
gpg --with-fingerprint --with-subkey-fingerprint  \
    --homedir=/tmp/mullvad-keyring \
    --keyring /tmp/mullvad-keyring/mullvad-keyring.kbx \
    --list-public-keys $KEY

# verfiy deb-packge signaure

echo "Check signature of downloaded deb-package"
gpgv --keyring /tmp/mullvad-keyring/mullvad-keyring.kbx \
     /tmp/mullvad-linux.deb.asc /tmp/mullvad-linux.deb || {
    "ERROR: Signature verifcation failed"; exit 6; }
echo "OK, signature of downloaded deb-package verified"
 
 
# check for systemctl
SYSTEMCTL_EXIST="true"
command -v systemctl >/dev/null || { 
	ln -s /bin/true /bin/systemctl;  
	SYSTEMCTL_EXIST="false"; 
}

# close any mullvadvpn client is running
#
echo "Closing Mullvad VPN clients"

pkill -f '/opt/Mullvad VPN/mullvad-vpn'
pkill -f '/opt/MullvadVPN/mullvad-vpn' 


# stop sysvinit mullvadvpn daemon 

if pidof /sbin/init >/dev/null && [ -x /etc/init.d/mullvadvpn ] ; then
    # stop mullvadvpn if running
    /etc/init.d/mullvad-daemon status >/dev/null 2>&1  &&  { 
    echo "Stopping mullvadvpn ...";    /etc/init.d/mullvad-daemon stop; }  
fi

# install Mullvad VPN deb-package
#
echo "Installing Mullvad VPN"
dpkg --unpack /tmp/mullvad-linux.deb

if pidof /sbin/init >/dev/null; then
  # rm postinst to finsh dpkg configure 
  rm -f /var/lib/dpkg/info/mullvad-vpn.postinst 
fi  
dpkg --configure mullvad-vpn
apt-get install -yf

# create symlink to avoid init.d error when starting with spaces in path
#
if [ -d '/opt/Mullvad VPN' ]; then
  [ -L /opt/MullvadVPN ] && rm /opt/MullvadVPN
  
  [ -d /opt/MullvadVPN ] && rm -r /opt/MullvadVPN
  ln -s '/opt/Mullvad VPN' /opt/MullvadVPN
fi

# start sysvinit mullvadvpn daemon and user client
#
if pidof /sbin/init 2>/dev/null && [ -x /etc/init.d/mullvad-daemon ] ; then
    # start mullvadvpn daemon if not running
    if ! /etc/init.d/mullvad-daemon status  >/dev/null 2>&1 ; then
        echo "Starting mullvadvpn ..."
        /etc/init.d/mullvad-daemon start
    fi
#    sleep 2 
#    # start mullvadvpn client
#    if /etc/init.d/mullvad-daemon status; then
#       if [ -x '/opt/MullvadVPN/mullvad-vpn' ] ; then
#        echo "Starting  Mullvad VPN client" 
#        su - $(logname) -c  '/opt/MullvadVPN/mullvad-vpn' >/dev/null 2>&1 & disown
#       else
#        echo "Warning: Mullvad VPN client not found" 
#       fi
#    fi
fi

# tidy up
[ "$SYSTEMCTL_EXIST" = "false" ] &&  rm /bin/systemctl 2>/dev/null
rm -r /tmp/mullvad-keyring 2>/dev/null
rm /tmp/mullvadvpn-linux.deb 2>/dev/null
rm /tmp/mullvadvpn-linux.deb.asc 2>/dev/null

echo "DONE!"
