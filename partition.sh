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

# Create GPT partition table
echo -e "o\nn\np\n1\n\n+${SWAP_SIZE}\nn\np\n2\n\n+${ROOT_SIZE}\nn\np\n3\n\n\nw" | fdisk $DISK_DEVICE

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