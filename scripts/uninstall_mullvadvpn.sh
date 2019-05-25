#!/bin/bash

# remove remaining conf files
#
if [ ! -f '/opt/Mullvad VPN/resources/mullvad-daemon' ] && \
   [   -d '/opt/Mullvad VPN' ]; then
   rm -r '/opt/Mullvad VPN'
fi
[ -L  /opt/MullvadVPN ] && rm  /opt/MullvadVPN
echo "DONE!"


