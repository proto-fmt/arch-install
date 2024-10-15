#!/bin/bash

# Ask user for disk device
echo "Enter the disk device (e.g. /dev/sda):"
read -r DISK_DEVICE

# Ask user for swap size
echo "Enter the swap partition size (e.g. 8G):"
read -r SWAP_SIZE

# Ask user for root size
echo "Enter the root partition size (e.g. 40G):"
read -r ROOT_SIZE

# Calculate remaining space for home partition
TOTAL_DISK_SIZE=$(blockdev --getsize64 $DISK_DEVICE)
HOME_SIZE=$((TOTAL_DISK_SIZE - 512M - SWAP_SIZE - ROOT_SIZE))

echo "Disk device: $DISK_DEVICE"
echo "EFI partition size: 512M"
echo "Swap partition size: $SWAP_SIZE"
echo "Root partition size: $ROOT_SIZE"
echo "Home partition size: $HOME_SIZE"

# Confirm before continuing
echo "Are you sure you want to create the partitions? (y/n)"
read -r CONFIRM

if [ "$CONFIRM" != "y" ]; then
  echo "Exiting..."
  exit 1
fi

# Create GPT label
parted -s $DISK_DEVICE mklabel gpt

# Create EFI partition
echo -e "mkpart primary fat32 1MiB 512MiB\n" | parted -s $DISK_DEVICE

# Create partitions
echo -e "mkpart primary linux-swap 512MiB +${SWAP_SIZE}\nmkpart primary ext4 +${SWAP_SIZE} +${ROOT_SIZE}\nmkpart primary ext4 +${ROOT_SIZE} 100%\n" | parted -s $DISK_DEVICE

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