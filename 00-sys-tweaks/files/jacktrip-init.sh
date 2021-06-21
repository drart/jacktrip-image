#!/bin/bash
#
# JackTrip Raspberry Pi Image: Initialization Service
# Copyright (c) 2020 JackTrip Foundation

CONFIG_DIR=/etc/jacktrip
ETC_AVAHI_SERVICES_DIR=/etc/avahi/services
TMP_AVAHI_SERVICES_DIR=/tmp/avahi/services
CREDENTIALS_FILE="${CONFIG_DIR}/credentials"
DEVICENAME_FILE="${CONFIG_DIR}/devicename"
DEVICETYPE_FILE="${CONFIG_DIR}/devicetype"

# get a random string (default 15). Optionally set a random length.
# random_string        -> 15 chars
# random_string 50     -> 50 chars
# random_string 20 80  -> will be between 20 and 80 chars long
# from https://www.supertechcrew.com/random-numbers-strings-bash-shell-scripting/#:~:text=Creating%20Random%20Numbers%20and%20Strings,--random-source=/dev/urandom%20-i%200-100%20-n%201
random_string() {
        local l=15
        [ -n "$1" ] && l=$1
        [ -n "$2" ] && l=$(shuf --random-source=/dev/urandom -i $1-$2 -n 1)
        tr -dc A-Za-z0-9 < /dev/urandom | head -c ${l} | xargs
}

# ensure that a line exists in /boot/config.txt
ini_ensure() {
    if [[ `grep "$1" "/boot/config.txt"` ]]; then
        sed -i.bak "s/$1/$2/" "/boot/config.txt"
    else
        echo $2 >> "/boot/config.txt"
    fi
}

# verify that a sound card is available via aplay command
function verify_card {
	echo "Checking for sound card NAME=$1 TYPE=$2"
	verify=$(aplay -l 2> /dev/null | grep "$1 \[${2}\]")
	if [ "$verify" != "" ]; then
		DEVICENAME="$1"
		DEVICETYPE="$2"
	fi
}

# add kernel overlay
function add_overlay {
	echo "Testing overlay $1"
	dtoverlay $1
	sleep 5
}

# remove kernel overlay
function remove_overlay {
	echo "Removing overlay $1"
	dtoverlay -R $1
	OVERLAYS="$1"
	while [ "$OVERLAYS" != "" ]; do
		sleep 1
		OVERLAYS=$(dtoverlay -l | grep "$1")
	done
}

# check for /proc/device-tree/hat
function check_hat {
	if [ -f /proc/device-tree/hat/product ]; then
		HATCARD=`cat /proc/device-tree/hat/product`
	else
		HATCARD=""
	fi
}

# detect supported sound card
function detect_card {
	check_hat

	# Check HiFiBerry DAC+ ADC Pro (setup via HAT EEPROM)
	if [ "$HATCARD" == "DAC+ ADC Pro" ]; then
		echo "Detected HiFiBerry DAC+ ADC Pro"

		# check if already configured
		verify_card "sndrpihifiberry" "snd_rpi_hifiberry_dacplusadcpro"
		if [ "$DEVICETYPE" != "" ]; then
			return
		fi

		# check if enabled in /boot/config.txt
		if [ `grep "^dtoverlay=hifiberry-dacplusadcpro" /boot/config.txt` ]; then
			echo "Failed to load overlay for HiFiBerry DAC+ ADC Pro"
			return
		fi

		# try enabling overlay
		ini_ensure '.*dtoverlay=hifiberry.*' 'dtoverlay=hifiberry-dacplusadcpro'
		sync
		reboot
	else
		if [ `grep "^dtoverlay=hifiberry-dacplusadcpro" /boot/config.txt` ]; then
		        sed -i.bak "s/^dtoverlay=hifiberry-dacplusadcpro/#dtoverlay=hifiberry-dacplusadcpro/" "/boot/config.txt"
		fi
	fi

	# Assume that the first ALSA card is the one we want to use (if it exists)
	DEVICETYPE=$(aplay -l 2> /dev/null | grep -m 1 'card [0-9]\+:' | sed 's/card [0-9]\+: \([^]]\+\) \[\([^]]\+\)\].*$/\2/')
	if [ "$DEVICETYPE" != "" ]; then
		DEVICENAME=$(aplay -l 2> /dev/null | grep -m 1 'card [0-9]\+:' | sed 's/card [0-9]\+: \([^]]\+\) \[\([^]]\+\)\].*$/\1/')
		return
	fi
	if [ "$HATCARD" != "" ]; then
		return -1
	fi

	# Check HiFiBerry DAC+ ADC Std (via dtoverlay dynamic load)
	add_overlay hifiberry-dacplusadc
	verify_card "sndrpihifiberry" "snd_rpi_hifiberry_dacplusadc"
	if [ "$DEVICETYPE" != "" ]; then
		return
	fi
	remove_overlay hifiberry-dacplusadc
	
	# Check HiFiBerry DIGI (via dtoverlay dynamic load)
	add_overlay hifiberry-digi
	verify_card "sndrpihifiberry" "snd_rpi_hifiberry_digi"
	if [ "$DEVICETYPE" != "" ]; then
		return
	fi
	remove_overlay hifiberry-digi

	# Check Audio Injector Stereo (via dtoverlay dynamic load)
	add_overlay audioinjector-wm8731-audio
	verify_card "audioinjectorpi" "audioinjector-pi-soundcard"
	if [ "$DEVICETYPE" != "" ]; then
		return
	fi
	remove_overlay audioinjector-wm8731-audio

	return -1
}

# update sound device
function update_device {

	# Detect sound card
	detect_card
	if [ "$DEVICETYPE" == "" ]; then
		echo "Unable to detect sound device"
		return -1
	fi
	echo "Found sound device NAME=$DEVICENAME TYPE=$DEVICETYPE"
	aplay -l

	# Ensure config directory exists
	if [ ! -d ${CONFIG_DIR} ]; then
		mkdir ${CONFIG_DIR}
	fi

	# Update device config files, if necessary
	if [ "$(cat ${DEVICENAME_FILE} 2> /dev/null)" != "$DEVICENAME" ]; then
		echo "Updating ${DEVICENAME_FILE}"
		echo $DEVICENAME > ${DEVICENAME_FILE}
	fi
	if [ "$(cat ${DEVICETYPE_FILE} 2> /dev/null)" != "$DEVICETYPE" ]; then
		echo "Updating ${DEVICETYPE_FILE}"
		echo $DEVICETYPE > ${DEVICETYPE_FILE}
	fi
}

# update /etc/issue
function update_issue {
	IP=$(hostname -I) || true
	MAC=$(cat /sys/class/net/eth0/address) || true
	APLAY=$(/usr/bin/aplay -l)

	if [ "$APLAY" == "" ]; then
		APLAY="No sound card found"
	fi

	cat << EOF >/etc/issue
Raspbian GNU/Linux 10 \\n \\l

My IP address is $IP
My MAC address is $MAC

$APLAY

EOF
}

# update API credentials, if necessary
function update_credentials {
	if [ ! `grep "^[a-zA-Z0-9]*\.[a-zA-Z0-9]*$" ${CREDENTIALS_FILE}` ]; then
		echo "Generating new credentials file: ${CREDENTIALS_FILE}"
		API_PREFIX=`random_string 7`
		API_SECRET=`random_string 32`
		echo "${API_PREFIX}.${API_SECRET}" > ${CREDENTIALS_FILE}
	fi
}

# update bluetooth config and start beacon
function update_bluetooth {
	MACADDR=`cat /sys/class/net/eth0/address`

	# Set bluetooth device name
	#if [ ! -f /etc/machine-info ]; then
	#	echo "PRETTY_HOSTNAME=\"JackTrip ${MACADDR}\"" > /etc/machine-info
	#	systemctl restart bluetooth
	#	hciconfig hci0 up
	#fi

	# Advertise Eddystone URL beacon for the device
	EDDYSTONE_BASE="1F 02 01 06 03 03 aa fe 17 16 aa fe 10 00 03"
	JKTP_NET_BASE="6a 6b 74 70 03"
	MACBASE64=`echo ${MACADDR} | xxd -r -p | base64`
	APISALT=`head -c3 /etc/jacktrip/credentials`
	URLDATA=`echo "d${MACBASE64}${APISALT}" | hexdump -v -e '/1 "%02x "' -n 12`
	hcitool -i hci0 cmd 0x08 0x0008 ${EDDYSTONE_BASE} ${JKTP_NET_BASE} ${URLDATA}
	echo "Broadcasting BLE Eddystone Beacon: https://jktp.net/d${MACBASE64}${APISALT}"

	# Advertise but don't allow connections
	hciconfig hci0 leadv 3
	hciconfig hci0 noscan
}

# update avahi services directory
function update_avahi_services {
	# Ensure etc services directory exists
	if [ ! -d ${ETC_AVAHI_SERVICES_DIR} ]; then
		mkdir -p ${ETC_AVAHI_SERVICES_DIR}
	fi

	# Ensure tmp services directory exists
	if [ ! -d ${TMP_AVAHI_SERVICES_DIR} ]; then
		mkdir -p ${TMP_AVAHI_SERVICES_DIR}
	fi

	# make sure ssh service file exists in tmp
	if [ ! -f "${TMP_AVAHI_SERVICES_DIR}/ssh.service" ]; then
		cp "/usr/share/doc/avahi-daemon/examples/ssh.service" "${TMP_AVAHI_SERVICES_DIR}/ssh.service"
	fi

	# bind mount tmp services to etc services
	mount --bind $TMP_AVAHI_SERVICES_DIR $ETC_AVAHI_SERVICES_DIR
	systemctl restart avahi-daemon
}


# Remount volumes read-write
mount -o remount,rw /
mount -o remount,rw /boot

# initialize config and services
update_issue
update_credentials
update_bluetooth
update_avahi_services
update_device

# Remount volumes read-only
mount -o remount,ro /
mount -o remount,ro /boot
