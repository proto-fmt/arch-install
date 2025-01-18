#!/bin/bash

# Add these safety flags at the beginning
set -euo pipefail
IFS=$'\n\t'

# ... existing code ...

# Improve the log() function with better formatting
log() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "${LOG_FILE:=/var/log/arch_install.log}"
}

# Add cleanup trap
cleanup() {
    local exit_code=$?
    info "Cleaning up..."
    # Ensure all partitions are unmounted
    umount -R /mnt 2>/dev/null || true
    swapoff "${DISK}2" 2>/dev/null || true
    if [ $exit_code -ne 0 ]; then
        error "Installation failed with exit code $exit_code"
    fi
    exit $exit_code
}
trap cleanup EXIT

# ... existing code ...

check_requirements() {
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root"
        exit 1
    }

    # Check if running on Arch Linux
    if [ ! -f /etc/arch-release ]; then
        error "This script must be run on Arch Linux live environment"
        exit 1
    }
}

# Improve disk selection validation
select_disk() {
    local available_disks
    available_disks=$(lsblk -lpdo NAME,SIZE,TYPE,MODEL | grep "disk")
    
    if [ -z "$available_disks" ]; then
        error "No available disks found"
        exit 1
    }

    # ... existing code ...
}

# Improve partition calculations with more precise math
prepare_disk() {
    # Use bc with better precision
    BC_ENV_ARGS="scale=3"
    export BC_ENV_ARGS

    # ... existing code ...

    # Improve secure disk wiping
    info "Securely wiping disk..."
    if command -v blkdiscard >/dev/null 2>&1; then
        blkdiscard "$DISK" 2>/dev/null || true
    else
        dd if=/dev/zero of="$DISK" bs=1M count=100 status=none
        dd if=/dev/zero of="$DISK" bs=1M seek=$((DISK_SIZE_GB * 1024 - 100)) count=100 status=none
    fi

    # ... existing code ...
}

# Add better error handling for package installation
install_base() {
    # ... existing code ...

    # Install packages with retry mechanism
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if pacstrap /mnt $PACKAGES; then
            success "Base system installed successfully"
            break
        else
            warning "Attempt $attempt of $max_attempts failed"
            if [ $attempt -eq $max_attempts ]; then
                error "Failed to install base system after $max_attempts attempts"
                exit 1
            fi
            sleep 5
            ((attempt++))
        fi
    done

    # ... existing code ...
}

# Add configuration validation
configure_system() {
    # ... existing code ...

    # Validate passwords with more secure requirements
    validate_password() {
        local pass="$1"
        if [[ ${#pass} -lt 8 ]]; then
            return 1
        elif ! [[ "$pass" =~ [A-Z] ]]; then
            return 1
        elif ! [[ "$pass" =~ [a-z] ]]; then
            return 1
        elif ! [[ "$pass" =~ [0-9] ]]; then
            return 1
        fi
        return 0
    }

    # ... existing code ...
}

# Improve main function with better progress tracking
main() {
    local -a steps=(
        "check_requirements"
        "check_boot_mode"
        "check_internet"
        "check_clock"
        "select_disk"
        "prepare_disk"
        "install_base"
        "configure_system"
    )
    
    local total_steps=${#steps[@]}
    local current_step=0

    for step in "${steps[@]}"; do
        ((current_step++))
        info "($current_step/$total_steps) Executing: ${step//_/ }"
        $step
    done
}