#!/bin/bash

# Color Configuration
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper Functions
log() {
    echo -e "${CYAN}[*] ${NC}$1"
}
error() {
    echo -e "${RED}[!] Error: ${NC}$1"
    exit 1
}
success() {
    echo -e "${GREEN}[+] ${NC}$1"
}
warning() {
    echo -e "${YELLOW}[!] Warning: ${NC}$1"
}


# Check boot mode (UEFI only)
check_boot_mode() {
    log "Checking boot mode..."
    if [ ! -d "/sys/firmware/efi" ]; then
        error "This script only supports UEFI systems"
    fi
    success "UEFI system detected"
}

# Check if internet is working
check_internet() {
    log "Checking internet connection..."
    if ! ping -c 1 -W 5 archlinux.org >/dev/null 2>&1; then
        error "No internet connection"
    fi
    success "Internet connection is working"
}



# Prepare disk for installation
prepare_disk() {
    log "Preparing disk for installation..."
    
    # Show available disks and get user input
    log "Available disks:"
    lsblk -lpdo NAME,SIZE,TYPE,MODEL
    echo

    while true; do
        read -p "Enter disk name (e.g. /dev/sda): " DISK
        DISK=${DISK%/} # Remove trailing slashes
        
        # Check if disk block device
        [[ ! -b "$DISK" ]] && { warning "Invalid disk name: $DISK"; continue; }

        # Check for system devices
        [[ "$DISK" =~ loop|sr|rom|airootfs ]] && { warning "Invalid! System device selected."; continue; }

        break
    done
    
    # Get disk size in GB and calculate available space
    DISK_SIZE=$(lsblk -b -n -o SIZE "$DISK" | head -n1)
    DISK_SIZE_GB=$((DISK_SIZE / 1024 / 1024 / 1024))
    AVAILABLE_SIZE=$((DISK_SIZE_GB - 1))  # Reserve 1GB for EFI partition
    
    log "Selected disk size: ${DISK_SIZE_GB} GB (${AVAILABLE_SIZE} GB available(1GB reserved for EFI))"

    # Get and validate swap size
    while true; do
        read -p "Enter SWAP partition size in GB (default: 8): " SWAP_SIZE
        SWAP_SIZE=${SWAP_SIZE:-8}
        
        if ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]]; then
            warning "Please enter a valid number"
        fi
        
        if [ "$SWAP_SIZE" -gt "$AVAILABLE_SIZE" ]; then
            warning "Swap size (${SWAP_SIZE} GB) exceeds available space (${AVAILABLE_SIZE} GB)"
        fi
        
        break
    done

    # Update available space and get root size
    AVAILABLE_SIZE=$((AVAILABLE_SIZE - SWAP_SIZE))
    log "Remaining space after swap: ${AVAILABLE_SIZE} GB"
    
    while true; do
        read -p "Enter root partition size in GB (default: 50): " ROOT_SIZE
        ROOT_SIZE=${ROOT_SIZE:-50}
        
        if ! [[ "$ROOT_SIZE" =~ ^[0-9]+$ ]]; then
            warning "Please enter a valid number"
        fi
        
        if [ "$ROOT_SIZE" -gt "$AVAILABLE_SIZE" ]; then
            warning "Root size (${ROOT_SIZE} GB) exceeds available space (${AVAILABLE_SIZE} GB)"
        fi
        
        break
    done
    
    # Calculate remaining space for home
    AVAILABLE_SIZE=$((AVAILABLE_SIZE - ROOT_SIZE))
    
    # Show current disk layout
    log "Current disk layout:"
    lsblk "$DISK"
    
    # Get user confirmation
    echo
    warning "WARNING: This will completely ERASE all data on $DISK"
    read -p "Are you sure you want to continue? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        error "Installation aborted by user"
    fi

    # Wipe all signatures from disk
    log "Wiping all signatures from disk..."
    wipefs -af "$DISK"
    
    # Zero out first and last 100MB of disk
    log "Securely wiping disk..."
    dd if=/dev/zero of="$DISK" bs=1M count=100 status=none
    dd if=/dev/zero of="$DISK" bs=1M seek=$((DISK_SIZE_GB * 1024 - 100)) count=100 status=none

    # Calculate partition points
    BOOT_START="1MiB"
    BOOT_END="1025MiB"
    SWAP_START="$BOOT_END"
    SWAP_END="$((SWAP_SIZE * 1024 + 1025))MiB"
    ROOT_START="$SWAP_END"
    ROOT_END="$((SWAP_SIZE * 1024 + ROOT_SIZE * 1024 + 1025))MiB"
    HOME_START="$ROOT_END"
    HOME_END="100%"

    # Create partitions
    log "Creating partitions..."
    parted -s "$DISK" \
        mklabel gpt \
        mkpart "EFI" fat32 $BOOT_START $BOOT_END \
        set 1 esp on \
        mkpart "Swap" linux-swap $SWAP_START $SWAP_END \
        mkpart "Root" ext4 $ROOT_START $ROOT_END \
        mkpart "Home" ext4 $HOME_START $HOME_END
            
    # Format partitions
    log "Formatting partitions..."
    mkfs.fat -F32 "${DISK}1"
    mkswap "${DISK}2"
    mkfs.ext4 -F "${DISK}3"
    mkfs.ext4 -F "${DISK}4"
        
    # Mount partitions
    log "Mounting partitions..."
    mount "${DISK}3" /mnt
    mkdir -p /mnt/boot/efi
    mount "${DISK}1" /mnt/boot/efi
    mkdir -p /mnt/home
    mount "${DISK}4" /mnt/home
    swapon "${DISK}2"
    
    DISK_PREPARED=1
    success "Disk partitioning completed"
}

install_base() {
    log "Installing base system..."
    
    # Determine CPU microcode based on the CPU model
    if lscpu | grep -q "Intel"; then
        MICROCODE="intel-ucode"
    elif lscpu | grep -q "AMD"; then
        MICROCODE="amd-ucode"
    else
        MICROCODE=""
    fi

    # Prepare packages
    PACKAGES="base base-devel linux linux-firmware grub efibootmgr sudo networkmanager"
    PACKAGES="$PACKAGES $MICROCODE"
    
    
    # Display packages to be installed
    echo "The following packages will be installed:"
    echo "$PACKAGES"
    
    read -p "Do you confirm the installation of these packages? (y/n, default: y): " CONFIRM
    CONFIRM=${CONFIRM:-y}

    if [ "$CONFIRM_INSTALL" != "y" ]; then
        error "Installation aborted."
    fi

    # Install packages
    pacstrap /mnt $PACKAGES
    
 
    success "Base system installed"
}

configure_system() {
    log "Configuring system..."

    # Get system configuration from user
    read -p "Enter hostname (default: archlinux): " HOSTNAME
    HOSTNAME=${HOSTNAME:-archlinux}
    while [[ ! $HOSTNAME =~ ^[a-zA-Z0-9-]+$ ]]; do
        error "Invalid hostname format"
        read -p "Enter hostname (default: archlinux): " HOSTNAME
        HOSTNAME=${HOSTNAME:-archlinux}
    done

    read -p "Enter username (default: user): " USERNAME
    USERNAME=${USERNAME:-user}
    while [[ ! $USERNAME =~ ^[a-z_][a-z0-9_-]*$ ]]; do
        error "Invalid username format"
        read -p "Enter username (default: user): " USERNAME
        USERNAME=${USERNAME:-user}
    done

    log "Available timezones:"
    timedatectl list-timezones | less
    read -p "Enter timezone (e.g. Europe/London): " TIMEZONE
    while [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]; do
        error "Invalid timezone"
        read -p "Enter timezone (e.g. Europe/London): " TIMEZONE
    done

    log "Available keymaps:"
    localectl list-keymaps | less
    read -p "Enter keymap (default: us): " KEYMAP
    KEYMAP=${KEYMAP:-us}
    while ! localectl list-keymaps | grep -q "^${KEYMAP}$"; do
        error "Invalid keymap"
        read -p "Enter keymap (default: us): " KEYMAP
        KEYMAP=${KEYMAP:-us}
    done

    while true; do
        read -s -p "Enter root password (min 8 chars): " ROOT_PASSWORD
        echo
        read -s -p "Confirm root password: " ROOT_PASSWORD_CONFIRM
        echo
        if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ] && [ ${#ROOT_PASSWORD} -ge 8 ]; then
            break
        fi
        error "Passwords don't match or too short"
    done

    while true; do
        read -s -p "Enter user password (min 8 chars): " USER_PASSWORD
        echo
        read -s -p "Confirm user password: " USER_PASSWORD_CONFIRM
        echo
        if [ "$USER_PASSWORD" = "$USER_PASSWORD_CONFIRM" ] && [ ${#USER_PASSWORD} -ge 8 ]; then
            break
        fi
        error "Passwords don't match or too short"
    done
    
    # Generate fstab
    genfstab -U /mnt > /mnt/etc/fstab
    
    # Configure system through chroot
    arch-chroot /mnt /bin/bash <<EOF
    # Timezone
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc
    
    # Localization
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
    
    # Hostname
    echo "$HOSTNAME" > /etc/hostname
    echo "127.0.0.1 localhost" >> /etc/hosts
    echo "::1       localhost" >> /etc/hosts
    echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts
    
    # Users and passwords
    echo "root:$ROOT_PASSWORD" | chpasswd
    useradd -m -G wheel -s /bin/bash $USERNAME
    echo "$USERNAME:$USER_PASSWORD" | chpasswd
    
    # Sudo configuration
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers.d/wheel
    
    # Bootloader
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
    
    # Enable services
    [ $INSTALL_NETWORK_MANAGER -eq 1 ] && systemctl enable NetworkManager
    [ $INSTALL_BLUETOOTH -eq 1 ] && systemctl enable bluetooth
EOF
    
    # Unmount everything before finishing
    log "Unmounting partitions..."
    umount -R /mnt || warning "Failed to unmount some partitions"
    
    success "System configuration completed"
}

# Main Installation
main() {
    clear
    log "### Welcome to Arch Linux installation ###"
    echo -e "${RED}WARNING:${NC} This script will ${RED}ERASE${NC} all data on the selected disk"
    echo -e "${YELLOW}ATENTION:${NC} This script doesn't support BIOS systems"

    
    check_boot_mode
    check_internet

    prepare_disk
    install_base
    configure_system

}

# Start installation
main