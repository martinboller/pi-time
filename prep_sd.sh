#!/bin/bash

#####################################################################
#                                                                   #
# Author:       Martin Boller                                       #
#                                                                   #
# Email:        martin@bollers.dk                                   #
# Last Update:  2021-11-14                                          #
# Version:      1.00                                                #
#                                                                   #
# Changes:  Tested on Debian 11 (Bullseye)                          #
#                                                                   #
#####################################################################
sudo touch /media/$USER/boot/ssh;
sudo nano /media/$USER/rootfs/etc/hostname;
sudo cp /home/$USER/git/pi-time/install-rpi-stratum1.sh /media/$USER/rootfs/root/;
sudo cp /home/$USER/git/pi-time/ntp_tips_tricks.txt /media/$USER/rootfs/root/;
sudo chmod +x /media/$USER/rootfs/root/install-rpi-stratum1.sh;
sync;