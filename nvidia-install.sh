#!/bin/bash

sudo pacman -Syu nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings vulkan-icd-loader lib32-vulkan-icd-loader opencl-nvidia lib32-opencl-nvidia cuda libva lib32-libva libva-utils vulkan-tools v4l-utils ffmpeg

printf '%s\n' 'options nvidia nvidia_drm.modeset=1 nvidia_drm.fbdev=1 NVreg_PreserveVideoMemoryAllocations=1 nvidia.NVreg_EnableGpuFirmware=0 NVreg_TemporaryFilePath=/var/tmp' | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null

printf '%s\n' 'blacklist i2c_nvidia_gpu' | sudo tee /etc/modprobe.d/nvidia-i2c.conf > /dev/null

printf '%s\n' 'blacklist nouveau' 'options nouveau modeset=0' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null

sudo sed -i '/^MODULES=/ s/)$/ nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf

sudo mkinitcpio -P
