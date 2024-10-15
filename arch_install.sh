#!/bin/bash

DRIVE="/dev/sda"

HOME_SIZE='5'
SWAP_SIZE='2'
EFI_SIZE='512'

LANG='en_US'

TIMEZONE='Asia/Yekaterinburg'

HOSTNAME='arch_pc'

ROOT_PASSWORD=''

USER_NAME='monkey'
USER_PASSWORD=''


# For Intel
VIDEO_DRIVER="i915"



source "./helpers.sh"

check_network() {
  description="Checking network"
  ping -c 1 archlinux.org &>/dev/null &
  track_command "$!" "$description"
}

detect_boot_type() {
  description="Detecting boot mode"
  mode=$(cat /sys/firmware/efi/fw_platform_size 2> /dev/null)
  check_error "$?" "$description" "UEFI(x$mode)"
  
 
}



check_network
detect_boot_type

check_network

