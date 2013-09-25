#!/bin/bash -e

DSLCORE_ISO="packages/dslcore_20080717.iso"
DSLCORE_MNT="/tmp/dslcore_mount"

DSL_AR="${DSLCORE_MNT}/boot/dslcore.gz"
DSL_CPIO="/tmp/dslcore"
DSL_DIR="boot"
IMG_FILENAME="output.img"
INSTALLER_SYSTEM_MNT="installer_system"
SECTOR_SIZE=512
IMAGE_SIZE=134217728

#
# Creating image file
#

dd if=/dev/zero of=${IMG_FILENAME} bs=${SECTOR_SIZE} count=$((IMAGE_SIZE / SECTOR_SIZE))
INSTALLER_SYSTEM_DEV=`losetup -f`
parted ${IMG_FILENAME} mklabel msdos
parted ${IMG_FILENAME} mkpart primary fat32 0 128
parted ${IMG_FILENAME} set 1 boot on
losetup ${INSTALLER_SYSTEM_DEV} ${IMG_FILENAME} -o 512
mkfs.vfat -F 32 -n "CXS_INSTALL" ${INSTALLER_SYSTEM_DEV}
mkdir -p ${INSTALLER_SYSTEM_MNT}
mount ${INSTALLER_SYSTEM_DEV} ${INSTALLER_SYSTEM_MNT}

#
# Unpacking DSL + CXS + installer onto image file
#
mkdir ${DSLCORE_MNT}
mount -o loop -t iso9660 ${DSLCORE_ISO} ${DSLCORE_MNT}
gunzip -c ${DSL_AR} > ${DSL_CPIO}
cpio -idmv < ${DSL_CPIO}

cp -vr ${DSL_DIR} ${INSTALLER_SYSTEM_MNT}
mv ${INSTALLER_SYSTEM_MNT}/${DSL_DIR}/isolinux/* ${INSTALLER_SYSTEM_MNT}
mv ${INSTALLER_SYSTEM_MNT}/isolinux.cfg ${INSTALLER_SYSTEM_MNT}/syslinux.cfg

#
# Install SYSLINUX on the image file
#

umount ${INSTALLER_SYSTEM_MNT}
syslinux ${INSTALLER_SYSTEM_DEV}
parted ${INSTALLER_SYSTEM_DEV} set 1 boot on

#
#Cleaning
#

rm -rf ${DSL_DIR}
rm -rf ${INSTALLER_SYSTEM_MNT}
losetup -d ${INSTALLER_SYSTEM_DEV}

