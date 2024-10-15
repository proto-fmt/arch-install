#!/bin/bash

echo "Enter the disk device (e.g. /dev/sda):"
read -r DRIVE
# Check if the DRIVE is empty
if [ -z "$DRIVE" ]; then
  echo "Error: Drive cannot be empty."
  exit 1
fi
# Check if the drive is a real disk
if !  [ "$(lsblk -d -o TYPE -n "$DRIVE")" = "disk" ]; then
  echo "Error: ${DRIVE} is not a valid disk device."
  exit 1
fi



echo "Enter the swap partition size (default 8G):"
read -r SWAP
# Set default swap size to 8G if empty
if [ -z "$SWAP" ]; then
  SWAP="8G"
fi

# Ask user for root size
echo "Enter the root partition size (e.g. 40G):"
read -r ROOT_SIZE

# Calculate partition sizes in bytes
EFI_SIZE=$((512 * 1024 * 1024))
SWAP_SIZE_BYTES=$((SWAP_SIZE * 1024 * 1024 * 1024))
ROOT_SIZE_BYTES=$((ROOT_SIZE * 1024 * 1024 * 1024))

# Calculate remaining space for home partition
TOTAL_DISK_SIZE=$(blockdev --getsize64 $DISK_DEVICE)
HOME_SIZE=$((TOTAL_DISK_SIZE - EFI_SIZE - SWAP_SIZE_BYTES - ROOT_SIZE_BYTES))

echo "Disk device: $DISK_DEVICE"
echo "EFI partition size: $EFI_SIZE bytes"
echo "Swap partition size: $SWAP_SIZE_BYTES bytes"
echo "Root partition size: $ROOT_SIZE_BYTES bytes"
echo "Home partition size: $HOME_SIZE bytes"

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