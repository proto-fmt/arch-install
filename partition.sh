#!/bin/bash

# Set variables
DRIVE=/dev/sda
EFI=1G
SWAP=1G
ROOT=10G

# Calculate remaining space for /home
TOTAL_SIZE=$(fdisk -s ${DRIVE})
HOME=$((TOTAL_SIZE - EFI - SWAP - ROOT))

# Ask user for confirmation
echo "This script will erase all data on ${DRIVE} and create the following partitions:"
echo "  - EFI: ${EFI}"
echo "  - SWAP: ${SWAP}"
echo "  - ROOT: ${ROOT}"
echo "  - HOME: ${HOME}G"
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  # Create GPT partition table
  sgdisk --clear ${DRIVE}
  sgdisk --new=1:0:+${EFI} --typecode=1:ef00 ${DRIVE}
  sgdisk --new=2:0:+${SWAP} --typecode=2:8200 ${DRIVE}
  sgdisk --new=3:0:+${ROOT} --typecode=3:8300 ${DRIVE}
  sgdisk --new=4:0:+${HOME}G --typecode=4:8300 ${DRIVE}

  # Set partition labels
  sgdisk --change-name=1:EFI ${DRIVE}
  sgdisk --change-name=2:SWAP ${DRIVE}
  sgdisk --change-name=3:ROOT ${DRIVE}
  sgdisk --change-name=4:HOME ${DRIVE}

  # Create file systems
  mkfs.vfat -F32 ${DRIVE}1
  mkswap ${DRIVE}2
  mkfs.ext4 ${DRIVE}3
  mkfs.ext4 ${DRIVE}4

  # Mount partitions
  mount ${DRIVE}3 /mnt
  mkdir /mnt/boot
  mount ${DRIVE}1 /mnt/boot
  mkdir /mnt/home
  mount ${DRIVE}4 /mnt/home
  swapon ${DRIVE}2
else
  echo "Partitioning cancelled."
fi