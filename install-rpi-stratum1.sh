#!/bin/bash

#####################################################################
#                                                                   #
# Author:       Martin Boller                                       #
#                                                                   #
# Email:        martin@bollers.dk                                   #
# Last Update:  2022-01-02                                          #
# Version:      4.10                                                #
#                                                                   #
# Changes:  Tested on Debian 11 (Bullseye)                          #
#           Minor updates+tested w. Jan 2021 Raspberrypi OS (3.56)  #
#           Cleaned update-leap service (3.54)                      #
#           Changed IPTABLES config (3.53)                          #
#           Optimized for Debian 11 (Bullseye) (4.00)               #
#           More Log and tty output & ntp.service (4.10)            #
#                                                                   #
#####################################################################

# Ensure the GPIO-serial port is not in use
configure_serial() {
    echo -e "\e[32mconfigure_serial()\e[0m";
    /usr/bin/logger 'configure_serial()' -t 'Stratum1 NTP Server';
    systemctl stop serial-getty@ttyAMA0.service;
    systemctl disable serial-getty@ttyAMA0.service;
    sed -i -e "s/console=serial0,115200//" /boot/cmdline.txt;
    echo -e "\e[32mconfigure_serial() finished\e[0m";
    /usr/bin/logger 'configure_serial() finished' -t 'Stratum1 NTP Server';
}

configure_locale() {
    echo -e "\e[32mconfigure_locale()\e[0m";
    /usr/bin/logger 'configure_locale()' -t 'Stratum1 NTP Server';
    echo -e "\e[36m..Configure locale (default:C.UTF-8)\e[0m";
    export DEBIAN_FRONTEND=noninteractive;
    update-locale LANG=en_GB.utf8;
    cat << __EOF__  > /etc/default/locale
# /etc/default/locale
LANG=C.UTF-8
LANGUAGE=C.UTF-8
LC_ALL=C.UTF-8
__EOF__
    echo -e "\e[32mconfigure_locale() finished\e[0m";
    /usr/bin/logger 'configure_locale() finished' -t 'Stratum1 NTP Server';
}

configure_timezone() {
    echo -e "\e[32mconfigure_timezone()\e[0m";
    /usr/bin/logger 'configure_timezone()' -t 'Stratum1 NTP Server';
    echo -e "\e[36m..Set timezone to Etc/UTC\e[0m";
    export DEBIAN_FRONTEND=noninteractive;
    rm /etc/localtime;
    echo 'Etc/UTC' > /etc/timezone;
    dpkg-reconfigure -f noninteractive tzdata;
    echo -e "\e[32mconfigure_timezone() finished\e[0m";
    /usr/bin/logger 'configure_timezone() finished' -t 'Stratum1 NTP Server';
}

install_updates() {
    echo -e "\e[32minstall_updates()\e[0m";
    /usr/bin/logger 'install_updates()' -t 'Stratum1 NTP Server';
    export DEBIAN_FRONTEND=noninteractive;
    sync \
    && echo -e "\e[36m..remove bluez\e[0m" && apt-get -y purge bluez \
    && echo -e "\e[36m..update\e[0m" && apt-get update \
    && echo -e "\e[36m..full-upgrade\e[0m" && apt-get -y full-upgrade \
    && echo -e "\e[36m..autoremove\e[0m" && apt-get -y --purge autoremove \
    && echo -e "\e[36m..autoclean\e[0m" && apt-get autoclean \
    && echo -e "\e[36m..Done\e[0m" \
    && sync;
    echo -e "\e[32minstall_updates() finished\e[0m";
    /usr/bin/logger 'install_updates() finished' -t 'Stratum1 NTP Server';
}

configure_gps() {
    /usr/bin/logger 'configure_gps()' -t 'Stratum1 NTP Server';
    echo -e "\e[32mconfigure_gps()\e[0m";
    ## Install gpsd
    export DEBIAN_FRONTEND=noninteractive;
    echo -e "\e[36m..Install gpsd\e[0m";
    apt-get -y install gpsd gpsd-clients;
    ## Setup GPSD
    echo -e "\e[36m..Setup gpsd\e[0m";
    systemctl stop gpsd.socket;
    systemctl stop gpsd.service;
    cat << __EOF__  > /etc/default/gpsd
# /etc/default/gpsd
## Stratum1
START_DAEMON="true"
GPSD_OPTIONS="-n"
DEVICES="/dev/ttyAMA0 /dev/pps0"
USBAUTO="false"
GPSD_SOCKET="/var/run/gpsd.sock"
__EOF__
    sync;
    systemctl restart gpsd.service;
    systemctl restart gpsd.socket;
    rm -f /etc/dhcp/dhclient-exit-hooks.d/ntp;
    echo -e "\e[36m..create rule for symbolic links\e[0m";
    cat << __EOF__  > /etc/udev/rules.d/99-gps.rules
## Stratum1
KERNEL=="pps0",SYMLINK+="gpspps0"
KERNEL=="ttyAMA0", SYMLINK+="gps0"
__EOF__
    echo -e "\e[32mconfigure_gps() finished\e[0m";
    /usr/bin/logger 'configure_gps() finished' -t 'Stratum1 NTP Server';
}

configure_pps() {
    echo -e "\e[32mconfigure_pps()\e[0m";
    /usr/bin/logger 'configure_pps()' -t 'Stratum1 NTP Server';
    export DEBIAN_FRONTEND=noninteractive;
    ## Install pps tools
    echo -e "\e[36m..Install PPS tools\e[0m";
    apt-get -y install pps-tools;
    ## create config.txt in boot also for RPI3 or 4
    echo -e "\e[36m..setup config.txt for PPS\e[0m";
    cat << __EOF__  >> /boot/config.txt
## Include ntp server specific settings to config.txt using include
include ntpserver.txt
__EOF__

    cat << __EOF__  > /boot/ntpserver.txt
# gps + pps + ntp settings
# https://github.com/raspberrypi/firmware/tree/master/boot/overlays
#Name:   pps-gpio
#Info:   Configures the pps-gpio, the pulse-per-second time signal via GPIO.
smsc95xx.turbo_mode=N
dtoverlay=pps-gpio,gpiopin=18
dtoverlay=pi3-miniuart-bt
enable_uart=1

## Constant CPU Speed kept at 1000 for better precision
## Normal governor=ondemand so between 600 and 1200 on RPi3 more on 4
force_turbo=1
arm_freq=1000
__EOF__
    ## ensure pps-gpio module loads
    echo -e "\e[36m..Add pps-gpio to modules for PPS\e[0m";
    echo 'pps-gpio' >> /etc/modules;
    echo -e "\e[32mconfigure_pps() finished\e[0m";
    /usr/bin/logger 'configure_pps() finished' -t 'Stratum1 NTP Server';
}

install_ntp_tools() {
    echo -e "\e[32minstall_ntp_tools()\e[0m";
    /usr/bin/logger 'install_ntp_tools()' -t 'Stratum1 NTP Server';
    export DEBIAN_FRONTEND=noninteractive;
    apt-get -y install ntpstat ntpdate;
    echo -e "\e[32minstall_ntp_tools() finished\e[0m";
    /usr/bin/logger 'install_ntp_tools() finished' -t 'Stratum1 NTP Server';
}

install_ntp() {
    /usr/bin/logger 'install_ntp()' -t 'Stratum1 NTP Server';
    echo -e "\e[32minstall_ntp()\e[0m";
    export DEBIAN_FRONTEND=noninteractive;
    apt-get -y install ntp;
    /usr/bin/logger 'install_ntp() finished' -t 'Stratum1 NTP Server';
    echo -e "\e[32minstall_ntp() finished\e[0m";
}

configure_ntp() {
    echo -e "\e[32mconfigure_ntp()\e[0m";
    echo -e "\e[36m..Stop ntpd\e[0m";
    systemctl stop ntp.service;

    echo -e "\e[36m..Update ntp.service\e[0m";
    sed -i "/After=/a Requires=gpsd.service" /lib/systemd/system/ntp.service;
    echo -e "\e[36m..Requires gpsd.service added to ntp.service\e[0m";

    cat << __EOF__  > /etc/ntp.conf
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

# Driver 28 Unit 1; SHM(1), gpsd: PPS data from shared memory provided by gpsd
# http://doc.ntp.org/current-stable/drivers/driver28.html
server  127.127.28.1  minpoll 3  maxpoll 3  true
fudge   127.127.28.1  refid SHM1  stratum 1

# Driver 28 Unit 2; SHM(2), gpsd: PPS data from shared memory provided by gpsd
# http://doc.ntp.org/current-stable/drivers/driver28.html
server  127.127.28.2  minpoll 3  maxpoll 3  true
fudge   127.127.28.2  refid SHM2  stratum 1

# Stratum-1 Servers to sync with - pick 4 to 6 good ones from
# http://support.ntp.org/bin/view/Servers/
#
## Select 4 to 6 servers  from https://support.ntp.org/bin/view/Servers/StratumOneTimeServers
## Below are some that work for Northern Europe
## 
server	ntp2.sptime.se	iburst
server	ntp2.fau.de	iburst
server	clock2.infonet.ee	iburst
server	rustime01.rus.uni-stuttgart.de	iburst
server	ntp01.hoberg.ch	iburst
		
#server	ntps1-0.eecsit.tu-berlin.de 	iburst
#server	ntp01.sixtopia.net	iburst
#server	gbg2.ntp.se 	iburst
#server	ntp4.sptime.se	iburst
#server	ntp.bcs2005.net 	iburst
		
#server	ptbtime2.ptb.de	iburst
#server	ntps1-1.eecsit.tu-berlin.de	iburst
#server	time.antwerpspace.be	iburst
#server	time.esa.int	iburst
#server	gbg1.ntp.se	iburst
		
#server	ntp.time.nl 	iburst
#server	ntp1.nl.uu.net	iburst
#server	ntp.certum.pl	iburst
#server	ntp1.oma.be	iburst
#server	ntp01.sixtopia.net 	iburst

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
__EOF__

    # Create directory for logfiles and let ntp own it
    echo -e "\e[36m..Create directory for logfiles and let ntp own it\e[0m";
    mkdir -p /var/log/ntpd
    chown ntp:ntp /var/log/ntpd
    sync;    
    ## Restart NTPD
    systemctl daemon-reload;
    systemctl restart ntp.service;
    echo -e "\e[32mconfigure_ntp() finished\e[0m";
    /usr/bin/logger 'configure_ntp() finished' -t 'Stratum1 NTP Server';
}

configure_update-leap() {
    echo -e "\e[32mconfigure_update-leap()\e[0m";
    /usr/bin/logger 'configure_update-leap()' -t 'Stratum1 NTP Server';
    echo -e "\e[36m..Creating service unit file\e[0m";
    cat << __EOF__  > /lib/systemd/system/update-leap.service
# service file running update-leap
# triggered by update-leap.timer

[Unit]
Description=service file running update-leap
Documentation=man:update-leap

[Service]
User=ntp
Group=ntp
ExecStart=-/usr/bin/wget -O /var/lib/ntp/leap-seconds.list https://www.ietf.org/timezones/data/leap-seconds.list
WorkingDirectory=/var/lib/ntp/

[Install]
WantedBy=multi-user.target
__EOF__

   echo -e "\e[36m..creating timer unit file\e[0m";

   cat << __EOF__  > /lib/systemd/system/update-leap.timer
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
__EOF__

    sync;
    echo -e "\e[36m..Get initial leap file and making sure timer and service can run\e[0m";
    systemctl daemon-reload;
    systemctl enable update-leap.timer;
    systemctl enable update-leap.service;
    systemctl start update-leap.timer;
    systemctl start update-leap.service;
    echo -e "\e[32mconfigure_update-leap() finished\e[0m";
    /usr/bin/logger 'configure_update-leap() finished' -t 'Stratum1 NTP Server';
}

configure_iptables() {
    echo -e "\e[32mconfigure_iptables()\e[0m";
    /usr/bin/logger 'configure_iptables()' -t 'Stratum1 NTP Server';
    echo -e "\e[32m-Creating iptables rules file\e[0m";
    # Bullseye does not have iptables by default, so installing
    # until converted to nftables
    apt-get -y install iptables;
    cat << __EOF__  >> /etc/network/iptables.rules
##
## Ruleset for Stratum-1 NTP Server
##
## IPTABLES Ruleset Author: Martin Boller 20190410 v3

*filter
## Dropping anything not explicitly allowed
##
:INPUT DROP [0:0]
:OUTPUT ACCEPT [0:0]

## Allow everything on loopback
-A INPUT -i lo -j ACCEPT

## SSH, DNS, WHOIS, DHCP ICMP - Add anything else here needed for ntp, monitoring, dhcp, icmp, updates, and ssh
##
## SSH
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
## NTP
-A INPUT -p udp -m udp --dport 123 -j ACCEPT
## ICMP
-A INPUT -p icmp -j ACCEPT
## Already established sessions
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
## Commit everything
COMMIT
__EOF__

    echo -e "\e[36m..Script applying iptables rules\e[0m";
    cat << __EOF__  >> /etc/network/if-up.d/firewallrules
#!/bin/sh
iptables-restore < /etc/network/iptables.rules
exit 0
__EOF__
    sync;
    ## make the script executable
    chmod +x /etc/network/if-up.d/firewallrules
    echo -e "\e[32mconfigure_iptables() finished\e[0m";
    /usr/bin/logger 'configure_iptables() finished' -t 'Stratum1 NTP Server';
}

configure_motd() {
    echo -e "\e[32mconfigure_motd()\e[0m";
    /usr/bin/logger 'configure_motd()' -t 'Stratum1 NTP Server';
    echo -e "\e[36m..Create motd file\e[0m";
    cat << __EOF__  >> /etc/motd

*******************************************
***                                     ***
***       Stratum 1 NTP Server          ***
***    -------------------------        ***          
***     Raspberry Pi Timeserver         ***
***                                     ***
***     Version 4.00 Nov 2021           ***
***                                     ***
********************||*********************
             (\__/) ||
             (•ㅅ•) ||
            /  　  づ
__EOF__
    
    sync;
    echo -e "\e[32mconfigure_motd() finished\e[0m";
    /usr/bin/logger 'configure_motd() finished' -t 'Stratum1 NTP Server';
}

install_ssh_keys() {
    echo -e "\e[32minstall_ssh_keys()\e[0m";
    /usr/bin/logger 'install_ssh_keys()' -t 'Stratum1 NTP Server';
    echo -e "\e[36m..Add public key to authorized_keys file\e[0m";
    # add SSH public key for root logon - change this to your own key
    mkdir /root/.ssh
    # Change to valid public key below 
    echo $myPublicSSHKey | tee /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 644 /root/.ssh/authorized_keys
    sync;
    echo -e "\e[32minstall_ssh_keys() finished\e[0m";
    /usr/bin/logger 'install_ssh_keys() finished' -t 'Stratum1 NTP Server';
}

configure_sshd() {
    echo -e "\e[32mconfigure_sshd()\e[0m";
    /usr/bin/logger 'configure_sshd()' -t 'Stratum1 NTP Server';
    # Disable password authN
    echo "PasswordAuthentication no" | tee -a /etc/ssh/sshd_config
    ## Generate new host keys
    echo -e "\e[36m..Delete and recreate host SSH keys\e[0m";
    rm -v /etc/ssh/ssh_host_*;
    dpkg-reconfigure openssh-server;
    echo -e "\e[32mconfigure_sshd() finished\e[0m";
    /usr/bin/logger 'configure_sshd() finished' -t 'Stratum1 NTP Server';
     sync;
}

disable_timesyncd() {
    echo -e "\e[32mDisable_timesyncd()\e[0m";
    /usr/bin/logger 'disable_timesyncd()' -t 'Stratum1 NTP Server';
    systemctl stop systemd-timesyncd
    systemctl disable systemd-timesyncd
    /usr/bin/logger 'disable_timesyncd() finished' -t 'Stratum1 NTP Server';
    echo -e "\e[32mDisable_timesyncd() finished\e[0m";
}

configure_dhcp() {
    echo -e "\e[32mconfigure_dhcp()\e[0m";
    /usr/bin/logger 'configure_dhcp()' -t 'Stratum1 NTP Server';
    ## Remove ntp and timesyncd exit hooks to cater for server using DHCP
    echo -e "\e[36m..Remove scripts utilizing DHCP\e[0m";
    rm /etc/dhcp/dhclient-exit-hooks.d/ntp
    rm /etc/dhcp/dhclient-exit-hooks.d/timesyncd
    ## Remove ntp.conf.dhcp if it exist
    echo -e "\e[36m..Removing ntp.conf.dhcp\e[0m";    
    rm -f /run/ntp.conf.dhcp
    ## Disable NTP option for dhcp
    echo -e "\e[36m..Disable ntp_servers option from dhclient\e[0m";   
    sed -i -e "s/option ntp_servers/#option ntp_servers/" /etc/dhcpcd.conf;
    ## restart NTPD yet again after cleaning up DHCP
    systemctl restart ntp
    echo -e "\e[32mconfigure_dhcp() finished\e[0m";
    /usr/bin/logger 'configure_dhcp() finished' -t 'Stratum1 NTP Server';
}

# If You've installed an RTC HWCLOCK on the I2C bus
# Verify which RTC chip is used
install_hwclock() {
    echo -e "\e[32mInstall_hwclock()\e[0m";
    /usr/bin/logger 'install_hwclock()' -t 'Stratum1 NTP Server';
    export DEBIAN_FRONTEND=noninteractive;
    echo -e "\e[36m..Install I2C tools\e[0m";
    apt-get -y install i2c-tools
    echo -e "\e[36m..Remove the Fake HWCLOCK\e[0m";
    apt-get -y remove fake-hwclock
    rm /etc/cron.hourly/fake-hwclock
    update-rc.d -f fake-hwclock remove
    rm /etc/init.d/fake-hwclock
    systemctl stop fake-hwclock.service
    systemctl disable fake-hwclock.service
    echo -e "\e[36m..Enable HWCLOCK\e[0m";
    update-rc.d hwclock.sh enable;
   
    #add to config.txt dtoverlay=i2c-rtc,pcf8563 - change to specifc RTC chip
    echo -e "\e[36m..Add dtoverlay to config.txt\e[0m";
    cat << __EOF__  >> /boot/ntpserver.txt
dtoverlay=i2c-rtc,pcf8563
__EOF__
    echo -e "\e[36m..Modify hwclock-set\e[0m";
    cat << __EOF__  >> /lib/udev/hwclock-set
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

__EOF__

    sync;
    dtoverlay i2c-rtc pcf8563;
    echo pcf8563 0x51 > /sys/class/i2c-adapter/i2c-1/new_device;
    hwclock --systohc --utc;
    echo -e "\e[1;31mRinstall_hwclock finished\e[0m";
    /usr/bin/logger 'install_hwclock() finished' -t 'Stratum1 NTP Server';
}

finish_reboot() {
    echo -e "\e[1;31mCountdown to reboot!\e[0m";
    /usr/bin/logger 'Countdown to reboot!' -t 'Stratum1 NTP Server'
    secs=30;
    echo -e;
    echo -e "\e[1;31m--------------------------------------------\e[0m";
        while [ $secs -gt 0 ]; do
            echo -ne "\e[1;32mRebooting in (seconds):  "
            echo -ne "\e[1;31m$secs\033[0K\r"
            sleep 1
            : $((secs--))
        done;
    sync;
    echo -e
    echo -e "\e[1;31mREBOOTING!\e[0m";
    /usr/bin/logger 'Rebooting!!' -t 'Stratum1 NTP Server'
    reboot;
}

configure_user_pi() {
    echo -e "\e[1;31mconfigure_user_pi()\e[0m";
    /usr/bin/logger 'configure_user_pi()' -t 'Stratum1 NTP Server'
    randompw=$(strings /dev/urandom | grep -o '[[:alnum:]]' | head -n 64 | tr -d '\n');
    echo pi:$randompw | chpasswd;
    usermod pi --lock;
    /usr/bin/logger 'configure_user_pi() finished' -t 'Stratum1 NTP Server'
    echo -e "\e[1;31mconfigure_user_pi() finished\e[0m";
}

configure_wifi() {
    echo -e "\e[1;31mconfigure_wifi()\e[0m";
    /usr/bin/logger 'configure_wifi()' -t 'Stratum1 NTP Server'
    rfkill unblock 0
    iw reg set $REGULATORY_COUNTRY;
    echo -e "\e[1;31mconfigure_wifi() finished\e[0m";
    /usr/bin/logger 'configure_wifi() finished' -t 'Stratum1 NTP Server'
}


#################################################################################################################
## Main Routine                                                                                                 #
#################################################################################################################
main() {

# SSH Public Key - Remember to change this, or you won't be able to login after running the script.
# Consider not running configure_user_pi until everything works.
myPublicSSHKey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIHJYsxpawSLfmIAZTPWdWe2xLAH758JjNs5/Z2pPWYm"
# Configure WiFi
REGULATORY_COUNTRY="DK"

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

configure_wifi;

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
# ppstest /dev/pps0
# ppswatch -a /dev/pps0
#
# gpsd -D 5 -N -n /dev/ttyAMA0 /dev/pps0 -F /var/run/gpsd.sock
# systemctl stop gpsd.*
# killall -9 gpsd
# dpkg-reconfigure -plow gpsd
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
