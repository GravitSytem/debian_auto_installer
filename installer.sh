#!/usr/bin/env bash

# Name 			: GravitInstaller.sh
# Description 	: This file is a simple script for installation of Gravit. This programme is executed by electron interface installer after user configuration
# Path 			: /subsystem/tmp/GravitInstaller.sh
# License		: GNU GPL v3

INSTALLATION_DIR="/mnt/debian"
TIMEZONE="Europe/Paris"
LANGUAGE="fr_FR.UTF-8"
KEYMAP="fr"
FQDN="Gravit"
ROOT_PASSWORD="toor"
ARCH="amd64"
DEBIAN_VERSION="jessie"
FS="ext4"
PARTITION_TYPE="gpt"
INSTALLATION_TYPE="bios"
INSTALLATION_ADDONS="laptop" # taskel package set (desktop, web-server, print-server, dns-server, file-server, mail-server, database-server, ssh-server, laptop, manuals)
DISK="sda"
SET_USER=1
USER="powersaucisse"
USER_PASSWD="gsupervisor"
log="/subsystem/var/log/Installation"
min_disk_size=50000

function usage() {
	echo
	echo " Usage"
	echo " ${0} -d sdX -w password -b partition type -f filesystem -k keymap -l lang -n hostname -t timezone -B bios/uefi -v debian version -a arch -s taskel sets"
	echo 
	echo " -d : Target device"
	echo " -w : Root password"
	echo " -b : Partition type (eg. gpt, msdos)"
	echo " -f : Filesystem (eg. ext4, btrfs, xfs ...)"
	echo " -k : Keymap (eg. en, it, fr, es ...)"
	echo " -l : Default language (eg. EN_us.UTF-8, IT_it.UTF-8 ...)"
	echo " -n : Hostname"
	echo " -t : Timezone (eg. Europe/Rome)"
	echo " -B : Installation type (eg. bios, uefi)"
	echo " -v : Debian version (eg. wheezy, jessie, sid)"
	echo " -a : Architecture (eg. amd64, i486 ...)"
	echo " -s : Taskel sets (eg. laptop, web-server, file-server ...)"
	exit 1
}


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

# show a warning before the installation

function warning() {
	loadkeys ${KEYMAP} || setxkbmap ${KEYMAP}
	echo "The script is going to destroy everithing on /dev/${DISK}."
	echo "Press RETURN to start installation or CTRL-C to cancel."
	read
}

# clear disk and create a partition layout

function format_disk() {
	echo " Clearing partition table on /dev/${DISK}"
	sgdisk --zap /dev/${DISK} >/dev/null 2>&1
	echo " Destroying magic strings and signatures on /dev/${DISK}"
	dd if=/dev/zero of=/dev/${DISK} bs=512 count=2048 >/dev/null 2>&1
	wipefs -a /dev/${DISK} 2>/dev/null
	echo " Writing partition table"
	parted -s /dev/${DISK} mktable ${PARTITION_TYPE} # voir mktable, possibilité d'erreur. confusion avec mklabel
	max=$(( $(cat /sys/block/${DISK}/size) * 512 / 1024 /1024 - 1))
	root_max=30
	if [ $max -le $(( ${root_max} * 1024)) ]
	then
		root_end=$(( $max / 2 ))
	else
		root_end=$(( ${root_max} * 1024 ))
	fi

	if [ ${INSTALLATION_TYPE} == "uefi" ]
	then
		boot_end=512
		echo " Creating /boot/efi partition"
		parted -a optimal -s /dev/${DISK} unit MiB mkpart ESI fat32 1 $boot_end >/dev/null
	elif [ ${INSTALLATION_TYPE} == "bios" ]
	then
		boot_end=128
		echo " Creating /boot partition"
		parted -a optimal -s /dev/${DISK} unit MiB mkpart primary 1 $boot_end >/dev/null
	fi

	echo " Creating / partition"
	parted -a optimal -s /dev/${DISK} unit MiB mkpart primary $boot_end $root_end >/dev/null
	echo " Creating /home partition"
	parted -a optimal -s /dev/${DISK} unit MiB mkpart primary $root_end $max >/dev/null

	if [ ${INSTALLATION_TYPE} == "uefi" ]
	then
		echo " Setting system bootable"
		parted -a optimal -s /dev/${DISK} set 1 boot on >/dev/null
	elif [ ${INSTALLATION_TYPE} == "bios" ]
	then
		echo " Setting system bootable"
		parted -a optimal -s /dev/${DISK} toggle 1 boot >/dev/null
		if [ ${PARTITION_TYPE} == "gpt" ]
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
	if [ ${INSTALLATION_TYPE} == "uefi" ]
	then
		echo " Making /boot/efi filesystem"
		mkfs.vfat -F32 /dev/${DISK}1 >/dev/null
	
	elif [ ${INSTALLATION_TYPE} == "bios" ]
	then
		echo " Making /boot filesystem"
		mkfs.ext2 /dev/${DISK}1 >/dev/null
	fi
	
	echo " Making / filesystem"
		mkfs.${FS} /dev/${DISK}2 >/dev/null
	echo " Making /home filesystem"
		mkfs.${FS} /dev/${DISK}3 >/dev/null

}
# mount disk 1. /dev/sdX2 --> / 2. /dev/sdx1 --> /boot/efi or /boot 3. /dev/sdx3 --> /home

function mount_disk() {
	echo " Mounting filesystems"
	mount -t ${FS} /dev/${DISK}2 ${INSTALLATION_DIR}
	if [ $INSTALLATION_TYPE == "uefi" ]
	then
		mkdir -p ${INSTALLATION_DIR}/{boot/efi,home}
		mount /dev/${DISK}1 ${INSTALLATION_DIR}/boot/efi >/dev/null
	elif [ ${INSTALLATION_TYPE} == "bios" ]
	then
		mkdir -p ${INSTALLATION_DIR}/{boot,home}
		mount -t ext2 /dev/${DISK}1 $INSTALLATION_DIR/boot >/dev/null
	fi

	mount -t ${FS} /dev/${DISK}3 ${INSTALLATION_DIR}/home

}

# install a base debian sistem in the INSTALLATION_DIR

function install_core() {
	echo " Installing core system"
	debootstrap --arch ${ARCH} ${DEBIAN_VERSION} ${INSTALLATION_DIR} >/dev/null # a modifier
	echo " Please wait (this operation can take a lot of time)"
}

# create a script inside the environmen built by debootstrap needed to complete the installation

function create_addons_installer() {
	# core system
	touch ${INSTALLATION_DIR}/usr/local/bin/deb_installer_core.sh
	echo "DEBIAN_FRONTEND=noninteractive apt-get -y update" >> ${INSTALLATION_DIR}/usr/local/bin/deb_installer_core.sh
	echo "DEBIAN_FRONTEND=noninteractive apt-get -y install linux-image-4.15.0-20-generic" >> ${INSTALLATION_DIR}/usr/local/bin/deb_installer_core.sh
	if [ ${INSTALLATION_TYPE} == "uefi" ]
	then
		echo "DEBIAN_FRONTEND=noninteractive apt-get -y install grub-efi-amd64 && update-grub && grub-install --target=x86_64-efi" >> ${INSTALLATION_DIR}/usr/local/bin/deb_installer_core.sh
	elif [ ${INSTALLATION_TYPE} == "bios" ]
	then
		echo "DEBIAN_FRONTEND=noninteractive apt-get -y install grub-pc grub-common && update-grub && grub-install /dev/${DISK}" >> ${INSTALLATION_DIR}/usr/local/bin/deb_installer_core.sh
	fi
	echo "tasksel install ${INSTALLATION_ADDONS} --new-install" >> ${INSTALLATION_DIR}/usr/local/deb_installer_core.sh
	# desktop environment
	case ${DE} in
		"xfce")
			;;
		"kde")
			;;
		"gnome")
			;;
		"lxde")
			;;
		"mate")
			;;
		"none")
			;;
		*)
			;;
	esac
}
	
function exec_addons_installer() {
	echo " Mounting environment filesystem" >> ${log}
	mount --bind /dev ${INSTALLATION_DIR}/dev >/dev/null
	mount --bind /sys ${INSTALLATION_DIR}/sys >/dev/null
	mount --bind /dev/pts ${INSTALLATION_DIR}/dev/pts >/dev/null
	mount -t proc none ${INSTALLATION_DIR}/proc >/dev/null
	cp -L /etc/resolv.conf ${INSTALLATION_DIR}/etc/ >/dev/null
	chroot ${INSTALLATION_DIR} /bin/bash /usr/local/bin/deb_installer_core.sh
}

function make_fstab() {
	# generating fstab line for /boot/efi or /boot
	echo " Generating /etc/fstab file" >> ${log}
	if [ ${INSTALLATION_TYPE} == "uefi" ]
	then
		echo "/dev/${DISK}1 /boot/efi vfat defaults 1 0" > ${INSTALLAYION_DIR}/etc/fstab
	elif [ ${INSTALLATION_TYPE} == "bios" ]
	then
		echo "/dev/${DISK}1 /boot ext2 noatime 1 0" > ${INSTALLATION_DIR}/etc/fstab
	fi
	# generating fstab line for /
	echo "/dev/${DISK}2 / ${FS} defaults 1 1" >> ${INSTALLATION_DIR}/etc/fstab
	# generating fstab line for /home
	echo "/dev/${DISK}3 /home ${FS} defaults 1 2" >> ${INSTALLATION_DIR}/etc/fstab
}

function add_conf_line() {
	echo $1 >> ${INSTALLATION_DIR}/usr/local/bin/deb_installer_configurator.sh
}

function create_conf() {
	echo " Configuring system"
	touch /usr/local/bin/deb_installer_configurator.sh 
	add_conf_line "echo ${FQDN} > /etc/hostname"
	add_conf_line 'echo "127.0.0.1 localhost" >> /etc/hosts'
	add_conf_line 'echo "127.0.1.1 ${FQDN}" >> /etc/hosts'
	add_conf_line 'echo -e "${ROOT_PASSWORD}\n${ROOT_PASSWORD}" | passwd root'

}

function apply_conf() {
	echo " Applying conf"
	chroot ${INSTALLATION_DIR} /bin/bash /usr/local/bin/deb_installer_configurator.sh
}

function manual_chroot() {
	echo " Would you like to do something in chroot?(Raccomanded)"
	echo " Press y(es) to start chroot or another key to umount disk"
	read key
	if [ $key == "y" ]
	then
		chroot ${INSTALLATION_DIR} /bin/bash
	fi
}

function umount_disk() {
	sync
	if [ ${INSTALLATION_TYPE} == "uefi" ]
	then
		echo " Umounting disk"
		umount -fv ${INSTALLATION_DIR}/boot/efi
	elif [ ${INSTALLATION_TYPE} == "bios" ]
	then
		echo " Umounting disk"
		umount -fv ${INSTALLATION_DIR}/boot
	fi
	umount -fv $INSTALLATION_DIR/{home,}
	echo " System installed"
}

OPTSTRING=d:w:b:f:k:hl:n:f:B:v:a:s:

while getopts ${OPTSTRING} OPT
do
	case ${OPT} in
		d)
			DISK=${OPTARG};;
		w)
			ROOT_PASSWORD=${OPTARG};;
		b)
			PARTITION_TYPE=${OPTARG};;
		f)
			FS=${OPTARG};;
		k)
			KEYMAP=${OPTARG};;
		h)
			usage ;;
		l)
			LANGAUGE=${OPTARG};;
		n)
			FQDN=${OPTARG};;
		f)
			TIMEZONE=${OPTARG};;
		B)
			INSTALLATION_TYPE=${OPTARG};;
		v)
			DEBIAN_VERSION=${OPTARG};;
		a)
			ARCH=${OPTARG};;
		s)
			INSTALLATION_ADDONS=${OPTARG};;
		X)
			DE=${OPTARG};;
		*)
			usage ;;
	esac
done

if  [ $(id -u) -ne 0 ]
then
	echo "2" > /subsystem/var/command_descriptor
	exit 1
fi

if [ ! -f /usr/share/zoneinfo/${TIMEZONE} ]
then
	echo " Invalid timezone"
	exit 1
fi

installation_summary
warning
format_disk
mount_disk
install_core
create_addons_installer
exec_addons_installer
make_fstab
create_conf
apply_conf
manual_chroot
umount_disk
