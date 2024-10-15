#!/bin/bash

# Ask user for disk device
echo "Enter the disk device (e.g. /dev/sda):"
read -r DISK_DEVICE

# Set partition sizes
SWAP_SIZE=1G
ROOT_SIZE=10G

# Calculate remaining space for home partition
TOTAL_DISK_SIZE=$(blockdev --getsize64 $DISK_DEVICE)
HOME_SIZE=$((TOTAL_DISK_SIZE - SWAP_SIZE - ROOT_SIZE))

echo "Disk device: $DISK_DEVICE"
echo "Swap partition size: $SWAP_SIZE"
echo "Root partition size: $ROOT_SIZE"
echo "Home partition size: $HOME_SIZE"

# Create GPT label
parted -s $DISK_DEVICE mklabel gpt

# Create partitions
echo -e "mkpart primary fat32 1MiB 2MiB\nmkpart primary linux-swap 2MiB +${SWAP_SIZE}\nmkpart primary ext4 +${SWAP_SIZE} +${ROOT_SIZE}\nmkpart primary ext4 +${ROOT_SIZE} 100%\n" | parted -s $DISK_DEVICE

# Format partitions
mkswap ${DISK_DEVICE}2
swapon ${DISK_DEVICE}2
mkfs.ext4 ${DISK_DEVICE}3
mkfs.ext4 ${DISK_DEVICE}4

# Mount partitions
mount ${DISK_DEVICE}3 /mnt
mkdir /mnt/boot
mount ${DISK_DEVICE}1 /mnt/boot
mkdir /mnt/home
mount ${DISK_DEVICE}4 /mnt/home