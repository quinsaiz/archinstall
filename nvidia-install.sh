#!/bin/bash
echo "Installing NVIDIA drivers and related packages..."

sudo pacman -S nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings vulkan-icd-loader lib32-vulkan-icd-loader opencl-nvidia lib32-opencl-nvidia libva lib32-libva libva-utils vulkan-tools mesa-utils v4l-utils ffmpeg

sudo pacman -S cuda 

read -p "Should create /etc/modprobe.d/nvidia*? [y/N]: " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    printf '%s\n' 'options nvidia NVreg_PreserveVideoMemoryAllocations=1 nvidia_drm.modeset=1 nvidia_drm.fbdev=1' | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null
    echo "nvidia parametrs config created."
    
    printf '%s\n' 'blacklist i2c_nvidia_gpu' | sudo tee /etc/modprobe.d/nvidia-i2c.conf > /dev/null
    echo "nvidia-i2c disabled config created."
    
    printf '%s\n' 'blacklist nouveau' 'options nouveau modeset=0' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null
    echo "blacklist noouveau config created."
    
    sudo sed -i '/^MODULES=/ s/)$/nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    echo "mkinitcpio modules updated."
    sudo mkinitcpio -P
else
    echo "Skip creating."
fi
