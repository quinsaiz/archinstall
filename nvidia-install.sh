#!/bin/bash

set -e

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)."
  exit 1
fi

KERNEL=$(uname -r)
DRIVER_PKG=""

# Kernel detection logic
if [[ "$KERNEL" == *"lts"* ]]; then
    DRIVER_PKG="nvidia-open-lts"
    echo "LTS kernel detected. Selected: $DRIVER_PKG"
elif [[ "$KERNEL" == *"arch"* ]] || [[ "$KERNEL" == *"linux"* ]]; then
    DRIVER_PKG="nvidia-open"
    echo "Standard kernel detected. Selected: $DRIVER_PKG"
else
    DRIVER_PKG="nvidia-open-dkms"
    echo "Custom/DKMS kernel detected ($KERNEL). Selected: $DRIVER_PKG"
fi

# Main logic
echo "--- Installing Base NVIDIA Packages ---"
pacman -S --needed $DRIVER_PKG nvidia-utils lib32-nvidia-utils nvidia-settings

echo "--- Installing Additional Components (Vulkan, FFmpeg) ---"
pacman -S --needed vulkan-icd-loader lib32-vulkan-icd-loader opencl-nvidia libva libva-utils vulkan-tools mesa-utils v4l-utils ffmpeg

echo "--- Configuring Modprobe Options ---"
printf '%s\n' 'options nvidia_drm modeset=1 fbdev=1' | tee /etc/modprobe.d/nvidia-drm.conf > /dev/null
printf '%s\n' 'blacklist i2c_nvidia_gpu' | tee /etc/modprobe.d/nvidia-i2c.conf > /dev/null
printf '%s\n' 'blacklist nouveau' 'options nouveau modeset=0' | tee /etc/modprobe.d/nouveau.conf > /dev/null

echo "--- Updating mkinitcpio ---"
if ! grep -q "nvidia nvidia_modeset nvidia_uvm nvidia_drm" /etc/mkinitcpio.conf; then
    sed -i '/^MODULES=(/ s/)/ nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sed -i 's/(  /( /g' /etc/mkinitcpio.conf
fi

echo "--- Regenerating initramfs ---"
mkinitcpio -P

echo "--- Installation Complete ---"
echo "cat /proc/driver/nvidia/params"
