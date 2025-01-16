#!/bin/bash

set -e

# Color Configuration
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helpers functions
info() {
    echo -e "${CYAN}[INFO] ${NC}$1"
}
error() {
    echo -e "${RED}[FAIL] ${NC}$1"
}
success() {
    echo -e "${GREEN}[OK] ${NC}$1"
}
warning() {
    echo -e "${YELLOW}[WARN] ${NC}$1"
}

separator() {
    echo "----------------------------------------"
}


##### Check if system is booted in UEFI mode
check_boot_mode() {
    echo "Checking boot mode..."
    if fw_size=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null); then
        success "${fw_size}-bit UEFI detected"
    else
        error "System not booted in UEFI mode"
        exit 1
    fi
}

##### Check internet connection
check_internet() {
    MAX_ATTEMPTS=3  # Number of attempts to connect to the internet
    WAIT_TIME=2     # Time to wait before retrying

    echo "Checking internet connection... "

    is_connected() {
        ping -c 1 -W 5 archlinux.org >/dev/null 2>&1
    }

    if is_connected; then
        success "Connected"
    else
        warning "No internet connection. Attempting to reconnect..."
        # Try to connect multiple times
        for ((i=1; i<=MAX_ATTEMPTS; i++)); do
            echo -n "Attempt $i/$MAX_ATTEMPTS... "
            sleep $WAIT_TIME  # Wait before retrying

            if is_connected; then
                success "Connected"
                break
            else
                echo -e "${RED}Failed${NC}"
            fi
        done
        error "No internet connection after $MAX_ATTEMPTS attempts"
        exit 1
    fi
}

##### Check system clock synchronization
check_clock() {
    MAX_ATTEMPTS=3  # Number of attempts to synchronize the clock
    WAIT_TIME=1     # Time to wait before retrying

    echo "Checking system clock synchronization... "

    # Local function to check sync status
    is_clock_synced() {
        timedatectl show --property=NTPSynchronized --value | grep -q "yes"
    }

    if is_clock_synced; then
        success "System clock is synchronized"
    else
        warning "System clock is not synchronized. Attempting to fix..."

        # Try to sync multiple times
        for ((i=1; i<=MAX_ATTEMPTS; i++)); do
            echo -n "Attempt $i/$MAX_ATTEMPTS... "
            timedatectl set-ntp true >/dev/null 2>&1
            sleep $WAIT_TIME

            if is_clock_synced; then
                success "System clock successfully synchronized"
                break
            fi  

            echo -e "${RED}Failed${NC}"
        done
        
        error "Could not synchronize clock after $MAX_ATTEMPTS attempts"
        exit 1
    fi  
}


##### Function to let user select disk
select_disk() {
    # Show available disks
    info "Available disks:"
    lsblk -lpdo NAME,SIZE,TYPE,MODEL
    echo

    while true; do
        read -p "Enter disk name (e.g. /dev/sda): " DISK
        DISK=${DISK%/} # Remove trailing slashes
        
        # Check if disk block device
        [[ ! -b "$DISK" ]] && { log_warning "Invalid disk name: $DISK"; continue; }

        # Check for system devices
        [[ "$DISK" =~ loop|sr|rom|airootfs ]] && { log_warning "Invalid! System device selected."; continue; }

        break
    done

    echo -e "${RED}WARNING: All data on $DISK ($DISK_SIZE_GB GB) will be erased!${NC}"
    read -p "Continue? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        error "Canceled by user"
        exit 1
    fi

    success "Selected disk: $DISK ($(lsblk -ndo SIZE "$DISK"))"
}

##### Prepare disk for installation
prepare_disk() {
    
    
    # Get disk size in GB and calculate available space
    DISK_SIZE=$(lsblk -b -n -o SIZE "$DISK" | head -n1)
    DISK_SIZE_GB=$((DISK_SIZE / 1024 / 1024 / 1024))
    AVAILABLE_SIZE=$((DISK_SIZE_GB - 1))  # Reserve 1GB for EFI partition
    
    info "Selected disk size: ${DISK_SIZE_GB}GB. ${AVAILABLE_SIZE}GB available (1GB reserved for EFI)"

    # Get and validate swap size
    while true; do
        read -p "Enter SWAP partition size in GB (default: 8): " SWAP_SIZE
        SWAP_SIZE=${SWAP_SIZE:-8}
        
        if ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]]; then
            warning "Please enter a valid number"
            continue
        fi
        
        if [ "$SWAP_SIZE" -gt "$AVAILABLE_SIZE" ]; then
            warning "SWAP size (${SWAP_SIZE} GB) is greater than available space (${AVAILABLE_SIZE} GB)"
            continue
        fi
        
        break
    done

    # Update available space and get root size
    AVAILABLE_SIZE=$((AVAILABLE_SIZE - SWAP_SIZE))
    info "Remaining space: ${AVAILABLE_SIZE} GB"
    
    while true; do
        read -p "Enter ROOT partition size in GB (default: 40): " ROOT_SIZE
        ROOT_SIZE=${ROOT_SIZE:-40}
        
        if ! [[ "$ROOT_SIZE" =~ ^[0-9]+$ ]]; then
            warning "Please enter a valid number"
            continue
        fi
        
        if [ "$ROOT_SIZE" -gt "$AVAILABLE_SIZE" ]; then
            warning "ROOT size (${ROOT_SIZE} GB) is greater than available space (${AVAILABLE_SIZE} GB)"
            continue
        fi
        
        break
    done
    
    # Calculate remaining space for home
    AVAILABLE_SIZE=$((AVAILABLE_SIZE - ROOT_SIZE))
    log "Remaining space: ${AVAILABLE_SIZE}GB. It will be used for the HOME partition."
    
        
    # Get user confirmation
    echo
    echo -e "${RED}WARNING:${NC} This will completely ${RED}ERASE${NC} all data on $DISK"
    read -p "Are you sure you want to continue? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        error "Installation aborted by user"
    fi

    # Wipe all signatures from disk
    info "Wiping all signatures from disk..."
    wipefs -af "$DISK"
    
    # Zero out first and last 100MB of disk
    info "Securely wiping disk..."
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
    info "Creating partitions..."
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
    
    success "Disk partitioning completed"
    # Show current disk layout
    info "Current disk layout:"
    lsblk "$DISK"
}

install_base() {
    echo "Installing base system..."
    
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
    
    read -p "Do you confirm the installation of these packages? (y/n): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        error "Installation aborted."
    fi

    # Install packages
    pacstrap /mnt $PACKAGES
    
 
    success "Base system installed"
}

configure_system() {
    echo "Configuring system..."

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

    info "Available timezones:"
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
    info "Unmounting partitions..."
    umount -R /mnt || warning "Failed to unmount some partitions"
    
    success "System configuration completed"
}

# Main Installation
main() {
    clear
    log "${CYAN}###${NC} Welcome to Arch Linux installation ${CYAN}###${NC}"
    echo 
    echo -e "${RED}WARNING:${NC} This script ${RED}WILL DELETE${NC} all data on the drive you selected."
    echo -e "${YELLOW}ATENTION:${NC} This script doesn't support BIOS systems"
    echo -e "${YELLOW}ATENTION:${NC} This script does not allow you to select disk partitions yourself, as well as file systems."
    echo -e "It will create the following partitions:"
    echo " * EFI (fat32): 1GB"
    echo " * SWAP (swap): YOUR INPUT"
    echo " * ROOT (ext4): YOUR INPUT"
    echo " * HOME (ext4): REMAINING DISK SPACE"
    echo
    separator
    echo
    read -p "Do you confirm the installation? (y/n): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        error "Installation aborted."
        exit 1
    fi

 
    check_boot_mode
    check_internet
    check_clock

    select_disk

   prepare_disk

    install_base

    configure_system

}

# Start installation
main