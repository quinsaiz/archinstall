#!/bin/bash

# Вибір диска для розмітки
disk="/dev/vda"

# Очищення диска і створення нової таблиці розділів GPT
echo "Clearing the disk and creating a new GPT partition table..."
parted $disk --script mklabel gpt

# Створення EFI розділу 512MB
echo "Creating a 512MB EFI partition..."
parted $disk --script mkpart primary fat32 1MiB 513MiB
parted $disk --script set 1 boot on

# Створення розділу для root на 25GB
echo "Creating a 25GB root partition..."
parted $disk --script mkpart primary 513MiB 25625MiB

# Перевірка, чи залишається вільне місце
parted $disk --script print free

# Форматування розділів
echo "Formatting partitions..."
mkfs.vfat -F32 ${disk}1 -n "EFI"
mkfs.f2fs -f -l "arch" ${disk}2

# Монтування розділів
echo "Mounting partitions..."
mount -t f2fs ${disk}2 /mnt
mkdir -p /mnt/boot/efi
mount ${disk}1 /mnt/boot/efi

echo "Partitioning and mounting complete."
