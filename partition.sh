#!/bin/bash

# Ask user for disk device
echo "Enter the disk device (e.g. /dev/sda):"
read -r DISK_DEVICE

# Set partition sizes
SWAP_SIZE=8G
ROOT_SIZE=40G

# Calculate remaining space for home partition
TOTAL_DISK_SIZE=$(blockdev --getsize64 $DISK_DEVICE)
HOME_SIZE=$((TOTAL_DISK_SIZE - SWAP_SIZE - ROOT_SIZE))

echo "Disk device: $DISK_DEVICE"
echo "Swap partition size: $SWAP_SIZE"
echo "Root partition size: $ROOT_SIZE"
echo "Home partition size: $HOME_SIZE"

# Create GPT partition table
sgdisk --zap-all $DISK_DEVICE
sgdisk --new=1:0:+$SWAP_SIZE --typecode=1:8200 $DISK_DEVICE
sgdisk --new=2:0:+$ROOT_SIZE --typecode=2:8300 $DISK_DEVICE
sgdisk --new=3:0:0 --typecode=3:8300 $DISK_DEVICE

# Format partitions
mkswap ${DISK_DEVICE}1
swapon ${DISK_DEVICE}1
mkfs.ext4 ${DISK_DEVICE}2
mkfs.ext4 ${DISK_DEVICE}3

# Mount partitions
mount ${DISK_DEVICE}2 /mnt
mkdir /mnt/boot
mount ${DISK_DEVICE}1 /mnt/boot
mkdir /mnt/home
mount ${DISK_DEVICE}3 /mnt/home