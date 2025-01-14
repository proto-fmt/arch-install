#!/bin/bash

#-----------------------------------------------------------------------------
# START OF CONFIGURATION SECTION
# EDIT THESE VARIABLES BEFORE RUNNING THE SCRIPT
#-----------------------------------------------------------------------------

# Disk configuration
DISK="/dev/sda"              # Target disk for installation
SWAP_SIZE="8"                # Swap partition size in GB
ROOT_SIZE="50"               # Root partition size in GB

# System configuration
HOSTNAME="archlinux"         # System hostname
USERNAME="user"              # Main user username
TIMEZONE="UTC"               # Timezone (e.g., "Europe/London")
KEYMAP="us"                  # Keyboard layout

# Passwords (CHANGE THESE!)
ROOT_PASSWORD="root_password"    # Root password
USER_PASSWORD="user_password"    # User password

# Package selection (1 to install, 0 to skip)
INSTALL_MICROCODE=1          # Install CPU microcode
INSTALL_NETWORK_MANAGER=1    # Install NetworkManager
INSTALL_BLUETOOTH=0          # Install bluetooth support
INSTALL_WIFI=0               # Install wifi support

# Additional packages (space-separated)
EXTRA_PACKAGES="vim git wget curl"

#-----------------------------------------------------------------------------
# END OF CONFIGURATION SECTION
# DO NOT EDIT BELOW THIS LINE IF YOU DON'T KNOW WHAT YOU'RE DOING
#-----------------------------------------------------------------------------



# Color Configuration
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'


# Helper Functions
log() {
    echo -e "${BLUE}[*] ${NC}$1"
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


# Function for validating user input
validate_config() {
    log "Validating configuration..."

    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root"
    }

    # Check if disk exists
    if [ ! -b "$DISK" ]; then
        error "Disk $DISK does not exist"
    fi

    # Validate numbers
    if ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]] || ! [[ "$ROOT_SIZE" =~ ^[0-9]+$ ]]; then
        error "SWAP_SIZE and ROOT_SIZE must be numbers"
    fi

    # Validate timezone
    if [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
        error "Invalid timezone: $TIMEZONE"
    fi

    # Validate keymap
    if ! localectl list-keymaps | grep -q "^${KEYMAP}$"; then
        error "Invalid keymap: $KEYMAP"
    fi

    # Check password length
    if [ ${#ROOT_PASSWORD} -lt 8 ] || [ ${#USER_PASSWORD} -lt 8 ]; then
        error "Passwords must be at least 8 characters long"
    fi

    # Validate username
    if [[ ! $USERNAME =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        error "Invalid username format"
    fi

    # Validate hostname
    if [[ ! $HOSTNAME =~ ^[a-zA-Z0-9-]+$ ]]; then
        error "Invalid hostname format"
    fi

    success "Configuration validated"
}


# Check if UEFI is supported
check_uefi() {
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
    
    # Show current disk layout
    log "Current disk layout:"
    lsblk "$DISK"
    
    # Confirmation
    log "WARNING: This will erase all data on $DISK"
    log "Planned partition scheme:"
    echo "- EFI partition: 512 MiB (FAT32)"
    echo "- Swap partition: ${SWAP_SIZE} GiB (swap)"
    echo "- Root partition: ${ROOT_SIZE} GiB (ext4)"
    echo "- Home partition: Remaining space (ext4)"
    
    read -p "Are you sure you want to continue? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        error "Installation aborted by user"
    fi

    # Calculate partition points
    EFI_START="1MiB"
    EFI_END="513MiB"
    SWAP_START="$EFI_END"
    SWAP_END="$((SWAP_SIZE * 1024 + 513))MiB"
    ROOT_START="$SWAP_END"
    ROOT_END="$((SWAP_SIZE * 1024 + ROOT_SIZE * 1024 + 513))MiB"
    HOME_START="$ROOT_END"
    HOME_END="100%"

    # Create partitions
    log "Creating partitions..."
    parted -s "$DISK" \
        mklabel gpt \
        mkpart "EFI" fat32 $EFI_START $EFI_END \
        set 1 esp on \
        mkpart "Swap" linux-swap $SWAP_START $SWAP_END \
        mkpart "Root" ext4 $ROOT_START $ROOT_END \
        mkpart "Home" ext4 $HOME_START $HOME_END
            
    # Format partitions
    log "Formatting partitions..."
    mkfs.fat -F32 "${DISK}1"
    mkswap "${DISK}2"
    mkfs.ext4 "${DISK}3"
    mkfs.ext4 "${DISK}4"
        
    # Mount partitions
    log "Mounting partitions..."
    mount "${DISK}3" /mnt
    mkdir -p /mnt/{boot/efi,home}
    mount "${DISK}1" /mnt/boot/efi
    mount "${DISK}4" /mnt/home
    swapon "${DISK}2"
    
    success "Disk partitioning completed"
}

install_base() {
    log "Installing base system..."
    
    # Prepare package list
    PACKAGES="base base-devel linux linux-firmware grub efibootmgr sudo $EXTRA_PACKAGES"
    
    # Add conditional packages
    [ $INSTALL_MICROCODE -eq 1 ] && PACKAGES="$PACKAGES intel-ucode amd-ucode"
    [ $INSTALL_NETWORK_MANAGER -eq 1 ] && PACKAGES="$PACKAGES networkmanager"
    [ $INSTALL_BLUETOOTH -eq 1 ] && PACKAGES="$PACKAGES bluez bluez-utils"
    [ $INSTALL_WIFI -eq 1 ] && PACKAGES="$PACKAGES iwd wpa_supplicant"
    
    # Install packages
    pacstrap /mnt $PACKAGES
    
    success "Base system installed"
}

configure_system() {
    log "Configuring system..."
    
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
    
    success "System configured"
}


# Main Installation
main() {
    clear
    log "Starting Arch Linux installation"
    
    validate_config
    check_uefi
    check_internet
    prepare_disk
    install_base
    configure_system
    
    # Unmount everything before finishing
    log "Unmounting partitions..."
    umount -R /mnt || warning "Failed to unmount some partitions"
    
    success "Installation completed successfully!"
    log "Please remove the installation media and reboot."
}

# Start installation
main