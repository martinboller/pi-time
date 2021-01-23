#!/bin/bash

touch /media/$USER/boot/ssh;
nano /media/$USER/rootfs/etc/hostname;
cp /home/$USER/git/pi-time/install-rpi-stratum1.sh /media/$USER/rootfs/root/;
