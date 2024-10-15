#!/bin/bash

install_packages() {
    # Update package database
    sudo pacman -Syy

    packages=(
        git 
        neov
        vi
        vim 
        nano 
        python3 
        python-pip 
        base-devel
    )

    for package in "${packages[@]}"; do
        sudo pacman -S --noconfirm "$package"
    done
}