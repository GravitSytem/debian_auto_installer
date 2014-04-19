#!/bin/bash

# automated debian install script
# require a debian/ubuntu live (booted via uefi for the efi installation), a internet connection and root access

INSTALLATION_DIR="/mnt/debian"
TIMEZONE="Europe/Rome"
LANG="it_IT.UTF-8"
KEYMAP="it"
FQDN="Gandalf.net"
ROOT_PASSWORD=""
ARCH="amd64"
DEBIAN_VERSION="jessie"
FS="ext4"
PARTITION_TYPE="gpt"
INSTALLATION_TYPE="uefi"
INSTALLATION_ADDONS="notebook"
DE="xfce"
DISK="/dev/sda"
SET_USER=1
USER="rmariotti"
USER_PASSWD=""

# Show a summary of the installation

function installation_summary() {
	echo
	echo "Installation Summary"
	echo
	echo " - Disk Target       = /dev/${DISK}"
	echo " - Disk Label        = ${PARTITION_TYPE}"
	echo " - Partition Scheme  = ${FS}"
	echo " - Hostname          = ${FQDN}"
	echo " - Timezone          = ${TMEZONE}"
	echo " - Keymap            = ${KEYMAP}"
	echo " - Locale            = ${LOCALE}"
	echo " - Debian Version    = ${DEBIAN_VERSION}"
	echo " - Root Password     = ${ROOT_PASSWORD}"
	echo " - Desktop           = ${DE}"
	if [ ${SET_USER} -eq 1 ]
	then
		echo " - Username          = ${USER}"
		echo " - User Password     = ${USER_PASSWORD}"
	fi
}

# Show a warning before the installation

function warning() {
	loadkeys ${KEYMAP}

	echo "The script is going to destroy everithing on /dev/${DISK}."
	echo "Press RETURN to start installation or CTRL-C to cancel."
	read
}

function format_disk() {
	echo " Clearing partition table on /dev/${DISK}"
	sgdisk --zap /dev/${DISK} >/dev/null 2>&1
	echo " Destroying magic strings and signatures on /dev/${DISK}"
	dd if=/dev/zero of=/dev/${DISK} bs=512 count=2048 >/dev/null 2>&1
	wipefs -a /dev/${DISK} 2>/dev/null
	echo " Writing partition table"
	pated -s /dev/${DISK} mktable ${PARTITION_TYPE}
	max=$(( $(cat /sys/block/${DISK}/size) * 512 / 1024 /1024 - 1))
	root_max=30
	if [ $max -le $(( ${root_max} * 1024)) ]
	then
		root_end=$(( $max / 2 ))
	else
		root_end=$(( ${root_max} * 1024 ))
	fi

	if [ ${INSTALLATION_TYPE} -eq "uefi" ]
	then
		boot_end=512
		echo " Creating /boot/efi partition"
		parted -a optimal -s /dev/${DISK} unit MiB mkpart ESI fat32 1 $boot_end >/dev/null
	elif [ ${INSTALLATION_TYPE} -eq "bios" ]
		boot_end=128
		" Creating /boot partition"
		parted -a optimal -s /dev/${DISK} unit MiB mkpart primary 1 $boot_end >/dev/null
	fi

	echo " Creating / partition"
	parted -a optimal -s /dev/${DISK} unit MiB mkpart primary $boot_end $root_end >/dev/null
	echo " Creating /home partition"
	parted -a optimal -s /dev/${DISK} unit MiB mkpart primary $root_end $max >/dev/null

	if [ ${INSTALLATION_TYPE} -eq "uefi" ]
	then
		echo " Setting system bootable"
		parted -a optimal -s /dev/${DISK} set 1 boot on >/dev/null
	elif [ ${INSTALLATION_TYPE} -eq "bios" ]
	then
		echo " Setting system bootable"
		parted -a optimal -s /dev/${DISK} toggle 1 boot >/dev/null
		if [ ${PARTITION_TYPE} -eq "gpt"]
		then
			sgdisk /dev/${DISK} --attributes=1:set:2 >/dev/null
		fi
	fi

	partprobe /dev/${DISK}
	if [[ $? -gt 0 ]]
	then
		echo "Partitionin Filed."
		exit 1
	fi

	udevadm settle

	# Creating Filesystems
	if [ ${INSTALLATION_TYPE} -eq "uefi" ]
	then
		echo " Making /boot/efi filesystem"
		mkfs.vfat -F32 /dev/${DISK}1 >/dev/null
	
	elif [ ${INSTALLATION_TYPE} -eq "bios" ]
	then
		echo " Making /boot filesystem"
		mkfs.ext2 /dev/${DISK}1 >/dev/null
	fi
	
	echo " Making / filesystem"
		mkfs.${FS} /dev/${DISK}2 >/dev/null
	echo " Making /home filesystem"
		mkfs.${FS} /dev/${DISK}3 >/dev/null



function mount_disk() {
	echo " Mounting filesystems"
	mount -t ${FS} /dev/${DISK}2 ${INSTALLATION_DIR}
	if [ $INSTALLATION_TYPE -eq "uefi" ]
	then
		mkdir -p ${INSTALLATION_DIR}/{boot/efi,home}
		mount /dev/${DISK}1 ${INSTALLATION_DIR}/boot/efi >/dev/null
	elif [ ${INSTALLATION_TYPE} -eq "bios" ]
	then
		mkdir -p ${INSTALLATION_DIR}/{boot,home}
		mount -t ext2 /dev/${DISK}1 $INSTALLATION_DIR/boot >/dev/null
	fi

	mount -t ${FS} /dev/${DISK}3 ${INSTALLATION_DIR}/home

}

function install_core() {
	echo " Installing core system"
	debootstrap --arch ${ARCH} ${DEBIAN_VERSION} ${INSTALLATION_DIR} >/dev/null
	echo " Mounting environment filesystem"
	mount --bind /dev ${INSTALLATION_DIR}/dev >/dev/null
	mount --bind /sys ${INSTALLATION_DIR}/sys >/dev/null
	mount --bind /dev/pts ${INSTALLATION_DIR}/dev/pts >/dev/null
	mount -t proc none ${INSTALLATION_DIR}/proc >/dev/null
	cp -L /etc/resolv.conf ${INSTALLATION_DIR}/etc/ >/dev/null
	chroot ${INSTALLATION_DIR} /bin/bash -c sh deb_installer_core.sh
}

function make_fstab() {
	# generating fstab line for /boot/efi or /boot
	echo " Generating /etc/fstab file"
	if [${INSTALLATON_TYPE} -eq "uefi"]
	then
		echo "${DISK}1 /boot/efi vfat defaults 1 0" > ${INSTALLAYION_DIR}/etc/fstab
	elif [${INSTALLATION_TYPE} -eq "bios"]
		echo "${DISK}1 /boot ext2 noatime 1 0" > ${INSTALLATION_DIR}/etc/fstab
	fi
	# generating fstab line for /
	echo "${DISK}2 / ${FS} defaults 1 1" >> ${INSTALLATION_DIR}/etc/fstab
	# generating fstab line for /home
	echo "${DISK}3 /home ${FS} defaults 1 2" >> ${INSTALLATION_DIR}/etc/fstab
}


function configure_system() {
	echo " Configure system"
	touch /usr/local/bin/deb_installer_configurator.sh >/dev/null

}
