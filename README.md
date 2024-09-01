<p align="center">
  <img src="https://upload.wikimedia.org/wikipedia/commons/1/13/Arch_Linux_%22Crystal%22_icon.svg" alt="Arch Linux" />
</p>

<h1 align="center">Arch Linux Automated Installation Script</h1>

Welcome to the Arch Linux Automated Installation Script repository! This project aims to simplify the installation process of Arch Linux by automating the setup steps, including disk partitioning, system configuration, and package installation. The script is designed to be flexible, allowing you to customize various aspects of the installation to suit your needs.

## Features

- **Automated Disk Partitioning**:
  - Supports both `ext4` and `f2fs` filesystems.
  - Automatically detects and handles different disk types (`/dev/sda`, `/dev/vda`, `/dev/nvme0n1`).
  - Validates partition sizes and available space to prevent errors during setup.

- **Flexible Installation Options**:
  - Choose between different kernel versions (e.g., LTS, Zen, etc.).
  - Create a swap file with customizable size.
  - Optional creation of a home partition or allocation of all remaining space to the root partition.

- **User-Friendly Prompts**:
  - Easy-to-understand prompts for user input.
  - Real-time feedback on available disk space after each partitioning step.
  - Color-coded output for error messages and success notifications.

- **System Configuration**:
  - Sets up essential system settings such as locale, timezone, and hostname.
  - Configures bootloader and enables necessary services.
  - Optionally installs and configures proprietary NVIDIA or open-source AMD drivers.

## Prerequisites

Before running this script, ensure you have:

- A system with an Internet connection.
- A UEFI or BIOS system.
- A desire to install Arch Linux!

## Installation

1. **Clone this repository**:
   ```bash
   git clone https://github.com/yourusername/archinstall.git
   cd archinstall

2. **Make the script executable and Run**:
    ```bash
    chmod +x arch.sh
    ./arch.sh
    ```
    
    Follow the prompts to customize your installation. The script will handle the rest!

## Usage

During execution, the script will ask for several inputs:

- **Disk Selection**: Choose the disk where you want to install Arch Linux.
- **Partition Sizes**: Enter sizes for EFI, root, and home partitions, with automatic size adjustment based on available space.
- **Filesystem Choice**: Select either `ext4` or `f2fs` for your root and home partitions.
- **Swap File**: Optionally create a swap file of your preferred size.
- **Kernel Selection**: Pick the desired kernel version for your installation.
- **Desktop Environment**: Select from GNOME, KDE Plasma, or skip desktop environment installation.

The script will then proceed to partition, format, and mount your selected disk, install Arch Linux, and configure essential system settings.

## Example

1. **Disk Partitioning**:
    - Enter size for EFI partition (minimum 512MB).
    - Enter size for root partition (in GB).
    - Optionally enter size for home partition (in GB) or press Enter to use the remaining space for root.

2. **Filesystem Selection**:
    - Choose between `ext4` or `f2fs` for the root partition.

3. **Kernel Selection**:
    - Choose between `linux`, `linux-lts`, or `linux-zen`.

4. **Desktop Environment**:
    - Choose between `gnome`, `kde`, or skip.

## Contributing

Feel free to contribute to the project by submitting issues or pull requests. Your feedback and contributions are welcome!

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
