#!/bin/bash

#####################################################################
#                                                                   #
# Author:       Martin Boller                                       #
#                                                                   #
# Email:        martin@bollers.dk                                   #
# Last Update:  2020-03-15                                          #
# Version:      3.55                                                #
#                                                                   #
# Changes:  Tested on Debian 10 (Buster)                            #
#           Cleaned update-leap service (3.54)                      #
#           Changed IPTABLES config (3.53)                          #
#           Cleanup of naming (3.52)                                #
#           Added logging (3.5 and 3.51)                            #
#           HWCLOCK (3.4)                                           #
#                                                                   #
#####################################################################

# Ensure the GPIO-serial port is not in use
configure_serial() {
    echo -e "\e[32mconfigure_serial()\e[0m";
    sudo systemctl stop serial-getty@ttyAMA0.service;
    sudo systemctl daemon-reload;
    sudo systemctl disable serial-getty@ttyAMA0.service;
    sudo sed -i -e "s/console=serial0,115200//" /boot/cmdline.txt;
    /usr/bin/logger 'configure_serial()' -t 'Stratum1 NTP Server';
}

configure_locale() {
    echo -e "\e[32mconfigure_locale()\e[0m";
    echo -e "\e[36m-Configure locale (default:C.UTF-8)\e[0m";
    export DEBIAN_FRONTEND=noninteractive;
    update-locale LANG=en_GB.utf8;
    sudo sh -c "cat << EOF  > /etc/default/locale
# /etc/default/locale
LANG=C.UTF-8
LANGUAGE=C.UTF-8
LC_ALL=C.UTF-8
EOF";
    /usr/bin/logger 'configure_locale()' -t 'Stratum1 NTP Server';
}

configure_timezone() {
    echo -e "\e[32mconfigure_timezone()\e[0m";
    echo -e "\e[36m-Set timezone to Etc/UTC\e[0m";
    export DEBIAN_FRONTEND=noninteractive;
    sudo rm /etc/localtime
    sudo sh -c "echo 'Etc/UTC' > /etc/timezone";
    sudo dpkg-reconfigure -f noninteractive tzdata;
    /usr/bin/logger 'configure_timezone()' -t 'Stratum1 NTP Server';
}

install_updates() {
    echo -e "\e[32minstall_updates()\e[0m";
    export DEBIAN_FRONTEND=noninteractive;
    sudo sync \
    && echo -e "\e[36m-update...\e[0m" && sudo apt-get -y purge bluez \
    && echo -e "\e[36m-update...\e[0m" && sudo apt-get update \
    && echo -e "\e[36m-upgrade...\e[0m" && sudo apt-get -y upgrade \
    && echo -e "\e[36m-dist-upgrade...\e[0m" && sudo apt-get -y dist-upgrade \
    && echo -e "\e[36m-autoremove...\e[0m" && sudo apt-get -y --purge autoremove \
    && echo -e "\e[36m-autoclean...\e[0m" && sudo apt-get autoclean \
    && echo -e "\e[36m-rpi-update...\e[0m" && echo y | sudo rpi-update \
    && echo -e "\e[36m-Done.\e[0m" \
    && sudo sync;
    /usr/bin/logger 'install_updates()' -t 'Stratum1 NTP Server';
}

configure_gps() {
    echo -e "\e[32mconfigure_gps()\e[0m";
    ## Install gpsd
    export DEBIAN_FRONTEND=noninteractive;
    echo -e "\e[36m-Install gpsd\e[0m";
    sudo apt-get -y install gpsd gpsd-clients;
    ## Setup GPSD
    echo -e "\e[36m-Setup gpsd\e[0m";
    sudo systemctl stop gpsd.socket;
    sudo systemctl stop gpsd.service;
    sudo sh -c "cat << EOF  > /etc/default/gpsd
# /etc/default/gpsd
## Stratum1
START_DAEMON=\"true\"
GPSD_OPTIONS=\"-n\"
DEVICES=\"/dev/ttyAMA0 /dev/pps0\"
USBAUTO=\"false\"
GPSD_SOCKET=\"/var/run/gpsd.sock\"
EOF";
    sync;
    sudo systemctl daemon-reload;
    sudo systemctl restart gpsd.service;
    sudo systemctl restart gpsd.socket;
    ## Configure GPSD socket
    grep -q Stratum1 /lib/systemd/system/gpsd.socket 2> /dev/null || {
        echo -e "\e[36m-Ensure that gpsd listens to all connection requests\e[0m";
        sudo sed /lib/systemd/system/gpsd.socket -i -e "s/ListenStream=127.0.0.1:2947/ListenStream=0.0.0.0:2947/";
        sudo sh -c "cat << EOF  >> /lib/systemd/system/gpsd.socket
;; Stratum1
EOF";
    }

    grep -q Stratum1 /etc/rc.local 2> /dev/null || {
        echo -e "\e[36m-Tweak GPS device at start up\e[0m";
        sudo sed /etc/rc.local -i -e "s/^exit 0$//";
        printf "## Stratum1
sudo systemctl stop gpsd.socket;
sudo systemctl stop gpsd.service;

# default GPS device settings at power on
stty -F /dev/ttyAMA0 9600

## custom GPS device settings
## 115200baud io rate,
#printf \x27\x24PMTK251,115200*1F\x5Cr\x5Cn\x27 \x3E /dev/ttyAMA0
#stty -F /dev/ttyAMA0 115200
## 10 Hz update interval
#printf \x27\x24PMTK220,100*2F\x5Cr\x5Cn\x27 \x3E /dev/ttyAMA0

sudo systemctl restart gpsd.service;
sudo systemctl restart gpsd.socket;

# Force gps service to wakeup
gpspipe -r -n 1 &

exit 0
" | sudo tee -a /etc/rc.local > /dev/null;
    }

    [ -f "/etc/dhcp/dhclient-exit-hooks.d/ntp" ] && {
        sudo rm -f /etc/dhcp/dhclient-exit-hooks.d/ntp;
    }

    [ -f "/etc/udev/rules.d/99-gps.rules" ] || {
        echo -e "\e[36m-create rule to create symbolic link\e[0m";
        sudo sh -c "cat << EOF  > /etc/udev/rules.d/99-gps.rules
## Stratum1
KERNEL==\"pps0\",SYMLINK+=\"gpspps0\"
KERNEL==\"ttyAMA0\", SYMLINK+=\"gps0\"
EOF";
    }
    /usr/bin/logger 'configure_gps()' -t 'Stratum1 NTP Server';
}

configure_pps() {
    echo -e "\e[32mconfigure_pps()\e[0m";
    export DEBIAN_FRONTEND=noninteractive;
    ## Install pps tools
    echo -e "\e[36m-Install PPS tools\e[0m";
    sudo apt-get -y install pps-tools;

    ## create config.txt in boot also for RPI3
    grep -q pps-gpio /boot/config.txt 2> /dev/null || {
        echo -e "\e[36m-setup config.txt for PPS\e[0m";
        sudo sh -c "cat << EOF  > /boot/config.txt
# /boot/config.txt
# https://www.raspberrypi.org/documentation/configuration/config-txt.md
## Stratum 1 NTP Server

[all]
max_usb_current=1
force_turbo=1

disable_overscan=1
hdmi_force_hotplug=1
config_hdmi_boost=4

#hdmi_ignore_cec_init=1
cec_osd_name=ntpserver

#########################################
# standard resolution
hdmi_drive=2

#########################################
# custom resolution
# 4k@24Hz or 25Hz custom DMT - mode
#gpu_mem=128
#hdmi_group=2
#hdmi_mode=87
#hdmi_pixel_freq_limit=400000000
#max_framebuffer_width=3840
#max_framebuffer_height=2160
#
#    #### implicit timing ####
#    hdmi_cvt 3840 2160 24
#    #hdmi_cvt 3840 2160 25
#
#    #### explicit timing ####
#    #hdmi_ignore_edid=0xa5000080
#    #hdmi_timings=3840 1 48 32 80 2160 1 3 5 54 0 0 0 24 0 211190000 3
#    ##hdmi_timings=3840 1 48 32 80 2160 1 3 5 54 0 0 0 25 0 220430000 3
#    #framebuffer_width=3840
#    #framebuffer_height=2160

# gps + pps + ntp settings
# https://github.com/raspberrypi/firmware/tree/master/boot/overlays
#Name:   pps-gpio
#Info:   Configures the pps-gpio (pulse-per-second time signal via GPIO).
#Load:   dtoverlay=pps-gpio,<param>=<val>
#Params: gpiopin                 Input GPIO (default "18")
#        assert_falling_edge     When present, assert is indicated by a falling
#                                edge, rather than by a rising edge
# dtoverlay=pps-gpio,gpiopin=4,assert_falling_edge
smsc95xx.turbo_mode=N
dtoverlay=pps-gpio,gpiopin=18
dtoverlay=pi3-miniuart-bt
enable_uart=1
EOF";
    }

    ## ensure pps-gpio module loads
    grep -q pps-gpio /etc/modules 2> /dev/null || {
        echo -e "\e[36m-Add pps-gpio to modules for PPS\e[0m";
        sudo sh -c "echo 'pps-gpio' >> /etc/modules";
    }
    /usr/bin/logger 'configure_pps()' -t 'Stratum1 NTP Server';
}

install_ntp_tools() {
    echo -e "\e[32minstall_ntp_tools()\e[0m";
    export DEBIAN_FRONTEND=noninteractive;
    sudo apt-get -y install ntpstat ntpdate;
    /usr/bin/logger 'install_ntp_tools()' -t 'Stratum1 NTP Server';
}

install_ntp() {
    echo -e "\e[32minstall_ntp()\e[0m";
    export DEBIAN_FRONTEND=noninteractive;
    sudo apt-get -y install ntp;
    /usr/bin/logger 'install_ntp()' -t 'Stratum1 NTP Server';
}

configure_ntp() {
    echo -e "\e[32mconfigure_ntp()\e[0m";
    echo -e "\e[36m-Stop ntpd\e[0m";
    sudo systemctl stop ntp.service;

    echo -e "\e[36m-Create new ntp.conf\e[0m";

    sudo sh -c "cat << EOF  > /etc/ntp.conf
##################################################
#
# GPS / PPS Disciplined NTP Server @ stratum-1
#      /etc/ntp.conf
#
##################################################

driftfile /var/lib/ntp/ntp.drift

# Statistics will be logged. Comment out next line to disable
statsdir /var/log/ntpstats/
statistics loopstats peerstats clockstats
filegen  loopstats  file loopstats  type week  enable
filegen  peerstats  file peerstats  type week  enable
filegen  clockstats  file clockstats  type week  enable

# Separate logfile for NTPD
logfile /var/log/ntpd/ntpd.log
logconfig =syncevents +peerevents +sysevents +allclock

# Driver 20; NMEA(0), /dev/gpsu, /dev/gpsppsu, /dev/gpsu: Generic NMEA GPS Receiver
# http://doc.ntp.org/current-stable/drivers/driver20.html
# time1 time:     Specifies the PPS time offset calibration factor, in seconds and fraction, with default 0.0.
# time2 time:     Specifies the serial end of line time offset calibration factor, in seconds and fraction, with default 0.0.
# stratum number: Specifies the driver stratum, in decimal from 0 to 15, with default 0.
# refid string:   Specifies the driver reference identifier, an ASCII string from one to four characters, with default GPS.
# flag1 0 | 1:    Disable PPS signal processing if 0 (default); enable PPS signal processing if 1.
# flag2 0 | 1:    If PPS signal processing is enabled, capture the pulse on the rising edge if 0 (default); capture on the falling edge if 1.
# flag3 0 | 1:    If PPS signal processing is enabled, use the ntpd clock discipline if 0 (default); use the kernel discipline if 1.
# flag4 0 | 1:    Obscures location in timecode: 0 for disable (default), 1 for enable.

###############################################################################################
# Driver 22 unit 0; kPPS(0), gpsd: /dev/pps0: Kernel-mode PPS ref-clock for the precise seconds
# http://doc.ntp.org/current-stable/drivers/driver22.html
# NTPD doesn't go below 3
#
server  127.127.22.0  minpoll 3  maxpoll 3  prefer  true
fudge   127.127.22.0  refid kPPS time1 0.002953
#
# time1 time:     Specifies the time offset calibration factor, in seconds and fraction, with default 0.0.
# time2 time:     Not used by this driver.
# stratum number: Specifies the driver stratum, in decimal from 0 to 15, with default 0.
# refid string:   Specifies the driver reference identifier, an ASCII string from one to four characters, with default PPS.
# flag1 0 | 1:    Not used by this driver.
# flag2 0 | 1:    Specifies PPS capture on the rising (assert) pulse edge if 0 (default) or falling (clear) pulse edge if 1. Not used under Windows - if the special serialpps.sys serial port driver is installed then the leading edge will always be used.
# flag3 0 | 1:    Controls the kernel PPS discipline: 0 for disable (default), 1 for enable. Not used under Windows - if the special serialpps.sys serial port driver is used then kernel PPS will be available and used.
# flag4 0 | 1:    Record a timestamp once for each second if 1. Useful for constructing Allan deviation plots.

###############################################################################################
# Driver 28 unit 0; SHM(0), gpsd: NMEA data from shared memory provided by gpsd
# http://doc.ntp.org/current-stable/drivers/driver28.html
#
server  127.127.28.0  minpoll 4  maxpoll 5  prefer  true
fudge   127.127.28.0  refid SHM0 stratum 5 flag1 1  time1 0.1387804
#
# time1 time:     Specifies the time offset calibration factor, in seconds and fraction, with default 0.0.
# time2 time:     Maximum allowed difference between remote and local clock, in seconds. Values  less 1.0 or greater 86400.0 are ignored, and the default value of 4hrs (14400s) is used instead. See also flag 1.
# stratum number: Specifies the driver stratum, in decimal from 0 to 15, with default 0.
# refid string:   Specifies the driver reference identifier, an ASCII string from one to four characters, with default SHM.
# flag1 0 | 1:    Skip the difference limit check if set. Useful for systems where the RTC backup cannot keep the time over long periods without power and the SHM clock must be able to force long-distance initial jumps. Check the difference limit if cleared (default).
# flag2 0 | 1:    Not used by this driver.
# flag3 0 | 1:    Not used by this driver.
# flag4 0 | 1:    If flag4 is set, clockstats records will be written when the driver is polled.

# Driver 28 Unit 2; SHM(2), gpsd: PPS data from shared memory provided by gpsd
# http://doc.ntp.org/current-stable/drivers/driver28.html
server  127.127.28.2  minpoll 3  maxpoll 3  true
fudge   127.127.28.2  refid SHM2  stratum 1

# Stratum-1 Servers to sync with - pick 4 to 6 good ones from
# http://support.ntp.org/bin/view/Servers/
#
# DK - Denmark
server ntp01.algon.dk iburst
server ntp2.sptime.se iburst
#server 80.71.132.103 iburst

# DE - Germany
server ntp2.fau.de iburst
server clock2.infonet.ee iburst
server rustime01.rus.uni-stuttgart.de  iburst
server ntp01.hoberg.ch iburst

# Access control configuration; see /usr/share/doc/ntp-doc/html/accopt.html for
# details.  The web page <http://support.ntp.org/bin/view/Support/AccessRestrictions>
# might also be helpful.
#
# Note that restrict applies to both servers and clients, so a configuration
# that might be intended to block requests from certain clients could also end
# up blocking replies from your own upstream servers.

# By default, exchange time with everybody, but do not allow configuration.
restrict -4 default kod notrap nomodify nopeer noquery
restrict -6 default kod notrap nomodify nopeer noquery

# Local users may interrogate the ntp server more closely.
restrict 127.0.0.1
restrict ::1

# Clients from this (example!) subnet have unlimited access, but only if
# cryptographically authenticated.
#restrict 192.168.123.0 mask 255.255.255.0 notrust

# If you want to provide time to your local subnet, change the next line.
# (Again, the address is an example only.)
#broadcast 192.168.123.255

# If you want to listen to time broadcasts on your local subnet, de-comment the
# next lines.  Please do this only if you trust everybody on the network!
#disable auth
#broadcastclient
#leap file location
leapfile /var/lib/ntp/leap-seconds.list
EOF";

    # Create folder for logfiles and let ntp own it
    echo -e "\e[36m-Create folder for logfiles and let ntp own it\e[0m";
    sudo mkdir /var/log/ntpd
    sudo chown ntp /var/log/ntpd
    sync;    
    ## Restart NTPD
    sudo systemctl restart ntp.service;
    /usr/bin/logger 'configure_ntp()' -t 'Stratum1 NTP Server';
}

configure_update-leap() {
    echo -e "\e[32mconfigure_update-leap()\e[0m";
    echo -e "\e[36m-Creating service unit file\e[0m";

    sudo sh -c "cat << EOF  > /lib/systemd/system/update-leap.service
# service file running update-leap
# triggered by update-leap.timer

[Unit]
Description=service file running update-leap
Documentation=man:update-leap

[Service]
User=ntp
Group=ntp
ExecStart=-/usr/bin/update-leap -F -f /etc/ntp.conf -s http://www.ietf.org/timezones/data/leap-seconds.list /var/lib/ntp/leap-seconds.list
WorkingDirectory=/var/lib/ntp/

[Install]
WantedBy=multi-user.target
EOF";

   echo -e "\e[36m-creating timer unit file\e[0m";

   sudo sh -c "cat << EOF  > /lib/systemd/system/update-leap.timer
# runs update-leap Weekly.
[Unit]
Description=Weekly job to check for updated leap-seconds.list file
Documentation=man:update-leap

[Timer]
# Don't run for the first 15 minutes after boot
OnBootSec=15min
# Run Weekly
OnCalendar=Weekly
# Specify service
Unit=update-leap.service

[Install]
WantedBy=multi-user.target
EOF";

    sync;
    echo -e "\e[36m-Get initial leap file and making sure timer and service can run\e[0m";
    wget -O /var/lib/ntp/leap-seconds.list http://www.ietf.org/timezones/data/leap-seconds.list;
    chmod +x /usr/local/bin/update-leap;
    sudo /usr/local/bin/update-leap;
    sudo systemctl daemon-reload;
    sudo systemctl enable update-leap.timer;
    sudo systemctl enable update-leap.service;
    sudo systemctl daemon-reload;
    sudo systemctl start update-leap.timer;
    sudo systemctl start update-leap.service;
    /usr/bin/logger 'configure_update-leap()' -t 'Stratum1 NTP Server';
}

configure_iptables() {
    echo -e "\e[32mconfigure_iptables()\e[0m";
    echo -e "\e[32m-Creating iptables rules file\e[0m";
    sudo sh -c "cat << EOF  >> /etc/network/iptables.rules
##
## Ruleset for Stratum-1 NTP Server
##
## IPTABLES Ruleset Author: Martin Boller 20190410 v3

*filter
## Dropping anything not explicitly allowed
##
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]

## Allow everything on loopback
-A INPUT -i lo -j ACCEPT

## SSH, DNS, WHOIS, DHCP ICMP - Add anything else here needed for ntp, monitoring, dhcp, icmp, updates, and ssh
##
## SSH
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
## DNS
-A OUTPUT -p tcp -m tcp --dport 53 -j ACCEPT
-A OUTPUT -p udp -m udp --dport 53 -j ACCEPT
-A OUTPUT -p tcp -m tcp --dport 853 -j ACCEPT
## HTTP(S)
-A OUTPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A OUTPUT -p tcp -m tcp --dport 443 -j ACCEPT
## NTP
-A INPUT -p udp -m udp --dport 123 -j ACCEPT
-A OUTPUT -p udp -m udp --dport 123 -j ACCEPT
## DHCP
-A OUTPUT -p udp -m udp --dport 67 -j ACCEPT
## ICMP
-A OUTPUT -p icmp -j ACCEPT
-A INPUT -p icmp -j ACCEPT
## Already established sessions
-A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
## Commit everything
COMMIT
EOF";

    echo -e "\e[36m-Script applying iptables rules\e[0m";
    sudo sh -c "cat << EOF  >> /etc/network/if-up.d/firewallrules
#!/bin/sh
iptables-restore < /etc/network/iptables.rules
exit 0
EOF";
    sync;
    ## make the script executable
    chmod +x /etc/network/if-up.d/firewallrules
    /usr/bin/logger 'configure_iptables()' -t 'Stratum1 NTP Server';
}

configure_motd() {
    echo -e "\e[32mconfigure_motd()\e[0m";
    echo -e "\e[36m-Create motd file\e[0m";
    sudo sh -c "cat << EOF  >> /etc/motd

*******************************************
***                                     ***
***       Stratum 1 NTP Server          ***
***    -------------------------        ***          
***     Raspberry Pi Timeserver         ***
***                                     ***
***     Version 3.53 May 2019           ***
***                                     ***
********************||*********************
             (\__/) ||
             (•ㅅ•) ||
            /  　  づ
EOF";
    
    sync;
    /usr/bin/logger 'configure_motd()' -t 'Stratum1 NTP Server';
}

install_ssh_keys() {
    echo -e "\e[32minstall_ssh_keys()\e[0m";
    echo -e "\e[36m-Add public key to authorized_keys file\e[0m";
    # Echo add SSH public key for root logon - change this to your own key
    sudo mkdir /root/.ssh
    # Change to valid public key below 
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIHJYsxpawSLfmIAZTPWdWe2xLAH758JjNs5/Z2pPWYm" | sudo tee /root/.ssh/authorized_keys
    sudo chmod 700 /root/.ssh
    sudo chmod 644 /root/.ssh/authorized_keys
    sync;
    /usr/bin/logger 'install_ssh_keys()' -t 'Stratum1 NTP Server';
}

configure_sshd() {
    echo -e "\e[32mconfigure_sshd()\e[0m";
    # Disable password authN
    echo "PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config
    ## Generate new host keys
    echo -e "\e[36m-Delete and recreate host SSH keys\e[0m";
    rm -v /etc/ssh/ssh_host_*;
    dpkg-reconfigure openssh-server;
    sync;
}

disable_timesyncd() {
    echo -e "\e[32mDisable_timesyncd()\e[0m";
    sudo systemctl stop systemd-timesyncd
    sudo systemctl daemon-reload
    sudo systemctl disable systemd-timesyncd
    /usr/bin/logger 'disable_timesyncd()' -t 'Stratum1 NTP Server';
}

configure_dhcp() {
    echo -e "\e[32mconfigure_dhcp()\e[0m";
    ## Remove ntp and timesyncd exit hooks to cater for server using DHCP
    echo -e "\e[36m-Remove scripts utilizing DHCP\e[0m";
    sudo rm /etc/dhcp/dhclient-exit-hooks.d/ntp
    sudo rm /etc/dhcp/dhclient-exit-hooks.d/timesyncd
    ## Remove ntp.conf.dhcp if it exist
    echo -e "\e[36m-Removing ntp.conf.dhcp\e[0m";    
    sudo rm /run/ntp.conf.dhcp
    ## Disable NTP option for dhcp
    echo -e "\e[36m-Disable ntp_servers option from dhclient\e[0m";   
    sudo sed -i -e "s/option ntp_servers/#option ntp_servers/" /etc/dhcpcd.conf;
    ## restart NTPD yet again after cleaning up DHCP
    sudo systemctl restart ntp
    /usr/bin/logger 'configure_dhcp()' -t 'Stratum1 NTP Server';
}

# If You've installed an RTC HWCLOCK on the I2C bus
# Verify which RTC chip is used
install_hwclock() {
    echo -e "\e[32mInstall_hwclock()\e[0m";
    export DEBIAN_FRONTEND=noninteractive;
    echo -e "\e[36m-Install I2C tools\e[0m";
    sudo apt-get -y install i2c-tools
    echo -e "\e[36m-Remove the Fake HWCLOCK\e[0m";
    sudo apt-get -y remove fake-hwclock
    sudo rm /etc/cron.hourly/fake-hwclock
    sudo update-rc.d -f fake-hwclock remove
    sudo rm /etc/init.d/fake-hwclock
    sudo systemctl stop fake-hwclock.service
    sudo systemctl daemon-reload 
    sudo systemctl disable fake-hwclock.service
    echo -e "\e[36m-Enable HWCLOCK\e[0m";
    sudo update-rc.d hwclock.sh enable;
   
    #add to config.txt dtoverlay=i2c-rtc,pcf8563 - change to specifc RTC chip
    echo -e "\e[36m-Add dtoverlay to config.txt\e[0m";
    sudo sh -c "cat << EOF  >> /boot/config.txt
dtoverlay=i2c-rtc,pcf8563
EOF";
    echo -e "\e[36m-Modify hwclock-set\e[0m";
    sudo sh -c "cat << EOF  >> /lib/udev/hwclock-set
#!/bin/sh
# Reset the System Clock to UTC if the hardware clock from which it
# was copied by the kernel was in localtime.

dev=$1

#if [ -e /run/systemd/system ] ; then
#    exit 0
#fi

if [ -e /run/udev/hwclock-set ]; then
    exit 0
fi

if [ -f /etc/default/rcS ] ; then
    . /etc/default/rcS
fi

# These defaults are user-overridable in /etc/default/hwclock
BADYEAR=no
HWCLOCKACCESS=yes
HWCLOCKPARS=
HCTOSYS_DEVICE=rtc0
if [ -f /etc/default/hwclock ] ; then
    . /etc/default/hwclock
fi

if [ yes = "$BADYEAR" ] ; then
    /sbin/hwclock --rtc=$dev --systz --badyear
    /sbin/hwclock --rtc=$dev --hctosys --badyear
else
    /sbin/hwclock --rtc=$dev --systz
    /sbin/hwclock --rtc=$dev --hctosys
fi

# Note 'touch' may not be available in initramfs
> /run/udev/hwclock-set

EOF";

    sync;
    sudo dtoverlay i2c-rtc pcf8563;
    sudo echo pcf8563 0x51 > /sys/class/i2c-adapter/i2c-1/new_device;
    sudo hwclock --systohc --utc;
    /usr/bin/logger 'install_hwclock()' -t 'Stratum1 NTP Server';
}

finish_reboot() {
    secs=10
    echo -e;
    echo -e "\e[1;31m--------------------------------------------\e[0m";
        while [ $secs -gt 0 ]; do
            echo -ne "Rebooting in: \e[1;31m$secs seconds\033[0K\r"
            sleep 1
            : $((secs--))
        done;
    sudo sync;
    echo -e
    echo -e "\e[1;31mREBOOTING!\e[0m";
    /usr/bin/logger 'finalized installation of stratum-1 server' -t 'Stratum1 NTP Server'
    reboot;
}

configure_user_pi() {
    randompw=$(strings /dev/urandom | grep -o '[[:alnum:]]' | head -n 30 | tr -d '\n');
    echo pi:$randompw | sudo chpasswd;
    sudo usermod pi --lock;
}


#################################################################################################################
## Main Routine                                                                                                 #
#################################################################################################################
main() {

echo -e "\e[32m-----------------------------------------------------\e[0m";
echo -e "\e[32mStarting Installation of NTP Server\e[0m";
echo -e "\e[32m-----------------------------------------------------\e[0m";
echo -e;

configure_serial;

configure_locale;

configure_timezone;

install_updates;

configure_gps;

configure_pps;

disable_timesyncd;

install_ntp_tools;

install_ntp;

configure_ntp;

configure_dhcp;

configure_update-leap;

install_ssh_keys;

configure_sshd;

configure_iptables;

configure_motd;

#if RTC HWCLOCK installed
#install_hwclock;

## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
## Disable (lock) user pi on the RPi - only do this if you are sure the SSH keys work, or you've effectively shut the door on yourself
## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
configure_user_pi;

## Finish with encouraging message, then reboot
echo -e "\e[32mInstallation and configuration of Stratum-1 server complete.\e[0m";
echo -e "\e[1;31mAfter reboot, please verify GPSD and NTPD operation\e[0m";
echo -e;

finish_reboot;

}

main

exit 0

#################################################################################################
# Information: Use these commands for t-shooting                                                #
#################################################################################################
#
# Check syslog for 'finalized installation of stratum-1 server'
#   then at least the script finished, but there should also be
#   a log entry for each routine called (main)
#
# dmesg | grep pps
# sudo ppstest /dev/pps0
# sudo ppswatch -a /dev/pps0
#
# sudo gpsd -D 5 -N -n /dev/ttyAMA0 /dev/pps0 -F /var/run/gpsd.sock
# sudo systemctl stop gpsd.*
# sudo killall -9 gpsd
# sudo dpkg-reconfigure -plow gpsd
#
# cgps -s
# gpsmon
# ipcs -m
# ntpshmmon
#
# using the ntp daemon
# ntpq -crv -pn
# watch -n 10 'ntpstat; ntpq -p -crv; ntptime;'
# watch -n 10 'hostname -s; echo -----------; ntpstat; ntpq -p -crv; ntptime;'
#
# Using Chrony
# watch -n5 'hostname -s; echo --------; chronyc sources -v; chronyc tracking;'
#
# If HW clock installed
# dmesg | grep rtc
# hwclock --systohc --utc
# hwclock --show --utc --debug
# cat /sys/class/rtc/rtc0/date
# cat /sys/class/rtc/rtc0/time
# cat /sys/class/rtc/rtc0/since_epoch
# cat /sys/class/rtc/rtc0/name
# i2cdetect -y 1
#
# Update system
# export DEBIAN_FRONTEND=noninteractive; apt update; apt dist-upgrade -y;
#
#################################################################################################
