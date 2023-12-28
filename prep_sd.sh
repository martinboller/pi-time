#!/bin/bash

#####################################################################
#                                                                   #
# Author:       Martin Boller                                       #
#                                                                   #
# Email:        martin@bollers.dk                                   #
# Last Update:  2023-12-28                                          #
# Version:      2.00                                                #
#                                                                   #
# Changes:  Tested on Debian 12 (Bookworm)                          #
#                                                                   #
#####################################################################

# Directory of script
export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

sudo touch /media/$USER/bootfs/ssh;
sudo nano /media/$USER/rootfs/etc/hostname;
sudo cp $SCRIPT_DIR/install-rpi-stratum1.sh /media/$USER/rootfs/root/;
sudo cp $SCRIPT_DIR/.env /media/$USER/rootfs/root/;
sudo cp $SCRIPT_DIR/ntp_tips_tricks.txt /media/$USER/rootfs/root/;
sudo chmod 755 /media/$USER/rootfs/root/install-rpi-stratum1.sh;
sync;