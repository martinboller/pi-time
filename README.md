# pi-time
Raspberry PI Stratum 1 server

# Raspberry Pi Installation script

### Bash script automating the installation of a GPS / PPS Disciplined Stratum-1 Server on the Raspberry Pi 4 

## prep_sd.sh prepares the SD-Card enabling SSH, copying the install script, and changes hostname

### Design principles:
  - Dedicated to being a Stratum-1 NTP server
  - Uses a GPS Breakout board


### Known issues:

### Latest changes 
#### 2021-12-02 - Bullseye version
  Version 4.00 now for Debian 11


### Installation
Prerequisite: A Raspberry PI 3 or 4
 - Write the latest Raspberry OS based on Debian 11 (Bullseye) to a good quality sd-card using dd or whatever tool you prefer
 - Run prep_sd.sh, enter a new hostname for the pi.
 - Boot the Pi, logon as pi/raspberrypi (user pi will be disabled later)
 - sudo su -
 - run ./install-rpi-stratum1.sh
 - Wait...
 - After reboot the Pi should now provide good time, however give it time :) lots of time to achieve good precision

### Hardware
It's easy to find GPS breakout boards for Arduino or Raspberry Pi's on ebay, amazon, and other semi-dubious marketplaces.
However there's also great boards from Adafruit and others.
 - Make sure the board outputs the PPS signal.
 - The serial I/O and PPS _must_ be 3.3v TTL level serial. If it's 5 volt serial, then level shifting is needed, however 
 - some boards can be supplied with 5v and still only outputs 3v3.
 - 5v output will kill the GPIO on the Raspberry Pi. Start with powering the GPS Board with 3v3 and see if that work.
 - Connect the ground of the GPS module to pin 6 of the GPIO header on the Raspberry Pi.
 - Connect either a +5 power input to pin 2 or a +3.3 power input of the GPIO header.
 - Connect the serial input of the GPS module to pin 8 and the serial output to pin 10 of the GPIO header.
 - Connect the PPS signal to pin 12 of the GPIO header.

Below is a picture of one I've used several of for exactly this purpose.

 ![alt text](./images/gps.png "GPS Ublox7")