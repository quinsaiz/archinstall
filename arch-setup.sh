#!/usr/bin/env bash
#
# arch-setup.sh - personal Arch Linux installer (UEFI, systemd-boot, btrfs/ext4)
#
#   ./arch-setup.sh           auto: "install" on the live ISO, "post" otherwise
#   ./arch-setup.sh install   base system, run as root from the live ISO
#   ./arch-setup.sh post      drivers, desktop, apps; run as your user after first boot
#   ./arch-setup.sh check     verify the finished system (run after the final reboot)
#
# Partitioning (cfdisk), Wi-Fi on the ISO, i2c fix are intentionally manual.

set -Eeuo pipefail
shopt -s inherit_errexit

SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
readonly SCRIPT_PATH
readonly TIMEZONE="Europe/Kyiv"
readonly DEFAULT_HOSTNAME="arch"
readonly STATE_FILE="/root/.arch-setup.env"
readonly BTRFS_OPTS="noatime,compress=zstd:3"
readonly ESP_OPTS="fmask=0077,dmask=0077"

# --------------------------------------------------------------------------- #
# Package lists
# --------------------------------------------------------------------------- #

GPU_COMMON_PKGS=(
	vulkan-icd-loader lib32-vulkan-icd-loader
	libva libva-utils vulkan-tools mesa-utils v4l-utils ffmpeg
)

FONT_PKGS=(
	ttf-liberation ttf-roboto ttf-jetbrains-mono-nerd
	noto-fonts noto-fonts-cjk noto-fonts-emoji
)

SOUND_PKGS=(
	pipewire pipewire-pulse pipewire-alsa pipewire-jack
	alsa-utils wireplumber easyeffects lsp-plugins-lv2 calf
)

KDE_PKGS=(
	plasma-desktop plasma-login-manager
	plasma-nm plasma-pa powerdevil kscreen
	kde-gtk-config breeze-gtk xdg-desktop-portal-kde
	plasma-systemmonitor kinfocenter plasma-firewall
	plasma-browser-integration
	kwallet kwallet-pam kwalletmanager
	qt6-tools
)
KDE_APPS=(konsole dolphin kate ark spectacle gwenview okular)

GNOME_REMOVE=(
	gnome-calendar gnome-characters gnome-clocks
	gnome-connections gnome-contacts gnome-music
	gnome-font-viewer gnome-maps gnome-software
	gnome-system-monitor gnome-tour gnome-weather
	baobab epiphany simple-scan papers snapshot
)

BASIC_PKGS=(
	git dosfstools ntfs-3g btop nvtop
	firefox telegram-desktop fastfetch luajit
	qbittorrent obs-studio papirus-icon-theme
	bash-completion
)
GNOME_ONLY_PKGS=(resources adw-gtk-theme gnome-browser-connector gnome-tweaks)

# --------------------------------------------------------------------------- #
# Output helpers
# --------------------------------------------------------------------------- #

if [[ -t 1 ]]; then
	C_RED=$'\e[31m'
	C_GREEN=$'\e[32m'
	C_YELLOW=$'\e[33m'
	C_BLUE=$'\e[34m'
	C_BOLD=$'\e[1m'
	C_OFF=$'\e[0m'
else
	C_RED=''
	C_GREEN=''
	C_YELLOW=''
	C_BLUE=''
	C_BOLD=''
	C_OFF=''
fi

info() { printf '\n%s==>%s %s%s%s\n' "$C_BLUE$C_BOLD" "$C_OFF" "$C_BOLD" "$*" "$C_OFF"; }
ok() { printf ' %s✔%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf ' %s!%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die() {
	printf '\n %s✘ %s%s\n' "$C_RED" "$*" "$C_OFF" >&2
	exit 1
}

trap 'die "Failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

# --------------------------------------------------------------------------- #
# Prompt helpers
# --------------------------------------------------------------------------- #

ask_yn() {
	local prompt=$1 default=${2:-n} reply hint='y/N'
	if [[ $default == y ]]; then hint='Y/n'; fi
	while true; do
		read -rp "$prompt [$hint]: " reply
		reply=${reply:-$default}
		case ${reply,,} in
		y | yes) return 0 ;;
		n | no) return 1 ;;
		esac
	done
}

ask_choice() {
	local -n __out=$1
	local prompt=$2 reply mark i
	shift 2
	local options=("$@")
	echo "$prompt"
	for i in "${!options[@]}"; do
		mark=''
		if ((i == 0)); then mark=' (default)'; fi
		printf '  %d) %s%s\n' $((i + 1)) "${options[i]}" "$mark"
	done
	while true; do
		read -rp "Choice [1]: " reply
		reply=${reply:-1}
		if [[ $reply =~ ^[0-9]+$ ]] && ((reply >= 1 && reply <= ${#options[@]})); then
			__out=${options[reply - 1]}
			return 0
		fi
	done
}

ask_input() {
	local -n __out=$1
	local prompt=$2 default=${3:-} reply
	read -rp "${prompt}${default:+ [$default]}: " reply
	__out=${reply:-$default}
}

ask_password() {
	local -n __out=$1
	local a b
	while true; do
		IFS= read -rsp "Repeat password: " b
		echo
		echo
		IFS= read -rsp "Repeat password: " b
		echo
		echo
		if [[ -n $a && $a == "$b" ]]; then
			__out=$a
			return 0
		fi
		warn "Passwords are empty or do not match, try again."
	done
}

ask_partition() {
	local -n __out=$1
	local reply
	while true; do
		read -rp "$2 (e.g. /dev/nvme0n1p2): " reply
		if [[ -b $reply && $(lsblk -dno TYPE "$reply") == part ]]; then
			__out=$reply
			return 0
		fi
		warn "'$reply' is not a partition."
	done
}

# --------------------------------------------------------------------------- #
# System helpers
# --------------------------------------------------------------------------- #

as_root() { if ((EUID == 0)); then "$@"; else sudo "$@"; fi; }
pac() { as_root pacman -S --needed "$@"; }
write_root() { as_root tee "$1" >/dev/null; }

check_network() {
	curl -fsI --max-time 5 https://archlinux.org >/dev/null ||
		die "No internet connection. $1"
}

# --------------------------------------------------------------------------- #
# Stage 1: install (live ISO)
# --------------------------------------------------------------------------- #

print_partition_help() {
	cat <<EOF

${C_BOLD}Partitioning is manual (cfdisk). What to do:${C_OFF}

  EFI partition (ESP)
    - Dual boot with Windows: REUSE the existing "EFI System" partition.
      Do not delete it. Do NOT format it in this script either.
    - Fresh disk: create a new 1 GiB partition of type "EFI System".
      The kernel and initramfs live on the ESP, so 512 MiB or more is advised.

  Root partition
    - Type "Linux filesystem".
    - btrfs: use all the remaining space (/home becomes a subvolume).
    - ext4: 50-100 GiB, and optionally one more partition for /home.

  Finish with: [ Write ] -> type "yes" -> [ Quit ].
EOF
}

collect_install_config() {
	info "Partitions"
	print_partition_help
	echo
	lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTTYPENAME,MOUNTPOINTS

	if ask_yn "Open cfdisk now?" n; then
		local disk
		echo
		echo "Available disks:"
		lsblk -d -e 7,11 -o NAME,SIZE,MODEL,TRAN
		while true; do
			read -rp "Disk to partition (e.g. /dev/nvme0n1, empty = skip): " disk
			if [[ -z $disk ]]; then break; fi
			if [[ -b $disk && $(lsblk -dno TYPE "$disk") == disk ]]; then
				cfdisk "$disk" || warn "cfdisk exited with an error."
				udevadm settle
				lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTTYPENAME,MOUNTPOINTS
				break
			fi
			warn "'$disk' is not a disk."
		done
	fi

	while true; do
		ask_partition ROOT_PART "Root partition"
		ask_partition ESP_PART "EFI (ESP) partition"
		if [[ $ROOT_PART == "$ESP_PART" ]]; then
			warn "Root and ESP must be different partitions."
		elif findmnt -rn -S "$ROOT_PART" >/dev/null; then
			warn "$ROOT_PART is mounted. Run 'umount -R /mnt' in another TTY (Alt+F2) and retry."
		else
			break
		fi
	done

	local esp_type
	esp_type=$(lsblk -dno PARTTYPENAME "$ESP_PART")
	if [[ $esp_type != *EFI* ]]; then
		warn "$ESP_PART has type '$esp_type', not 'EFI System'. The firmware may ignore it."
	fi

	FORMAT_ESP=no
	if ask_yn "Format the ESP? (answer NO when it is shared with Windows)" n; then
		FORMAT_ESP=yes
	fi

	info "Filesystem"
	ask_choice FS "Root filesystem:" btrfs ext4
	SNAPPER_SUBVOLS=no
	HOME_PART=''
	if [[ $FS == btrfs ]]; then
		if ask_yn "Create extra subvolumes for Snapper (@var_log, @pkg)?" n; then
			SNAPPER_SUBVOLS=yes
		fi
	else
		local reply
		while true; do
			read -rp "Separate /home partition (empty = none): " reply
			[[ -z $reply ]] && break
			if [[ -b $reply && $(lsblk -dno TYPE "$reply") == part &&
			$reply != "$ROOT_PART" && $reply != "$ESP_PART" ]]; then
				HOME_PART=$reply
				break
			fi
			warn "'$reply' is not a usable partition."
		done
	fi

	info "System"
	ask_choice KERNEL "Kernel:" linux-zen linux
	ask_choice LOCALE_MODE "Localization:" auto manual
	while true; do
		ask_input HOSTNAME_VALUE "Hostname" "$DEFAULT_HOSTNAME"
		[[ $HOSTNAME_VALUE =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] && break
		warn "Invalid hostname."
	done
	ask_password ROOT_PW "root"
	while true; do
		read -rp "Username: " USERNAME
		[[ $USERNAME =~ ^[a-z_][a-z0-9_-]{0,30}$ && $USERNAME != root ]] && break
		warn "Invalid username (lowercase letters, digits, _ and -)."
	done
	ask_password USER_PW "$USERNAME"
}

confirm_install() {
	local esp_note="kept as is (mounted at /boot)"
	if [[ $FORMAT_ESP == yes ]]; then esp_note="${C_RED}WILL BE FORMATTED${C_OFF}"; fi
	info "Summary"
	cat <<EOF
	Root partition : $ROOT_PART ($FS), currently: $(lsblk -dno FSTYPE,SIZE,LABEL "$ROOT_PART") - ${C_RED}WILL BE FORMATTED${C_OFF}
  EFI partition  : $ESP_PART - $esp_note
  Extra          : /home=${HOME_PART:-$([[ $FS == btrfs ]] && echo subvolume || echo "on root")}, Snapper subvolumes=$SNAPPER_SUBVOLS
  Kernel         : $KERNEL
  Localization   : $LOCALE_MODE
  Hostname/user  : $HOSTNAME_VALUE / $USERNAME
EOF
	local answer
	while true; do
		read -rp "Type 'yes' to erase the partitions above, or 'no' to start over: " answer
		case ${answer,,} in
		yes)
			CONFIRMED=yes
			break
			;;
		no)
			warn "Starting over."
			break
			;;
		*) warn "Please type 'yes' or 'no'." ;;
		esac
	done
}

setup_btrfs() {
	mkfs.btrfs -f -L arch "$ROOT_PART"
	mount "$ROOT_PART" /mnt
	btrfs subvolume create /mnt/@
	btrfs subvolume create /mnt/@home
	if [[ $SNAPPER_SUBVOLS == yes ]]; then
		btrfs subvolume create /mnt/@var_log
		btrfs subvolume create /mnt/@pkg
	fi
	umount /mnt

	mount -o "$BTRFS_OPTS,subvol=@" "$ROOT_PART" /mnt
	mount --mkdir -o "$BTRFS_OPTS,subvol=@home" "$ROOT_PART" /mnt/home
	if [[ $SNAPPER_SUBVOLS == yes ]]; then
		mount --mkdir -o "$BTRFS_OPTS,subvol=@var_log" "$ROOT_PART" /mnt/var/log
		mount --mkdir -o "$BTRFS_OPTS,subvol=@pkg" "$ROOT_PART" /mnt/var/cache/pacman/pkg
	fi
}

setup_ext4() {
	mkfs.ext4 -F -L arch "$ROOT_PART"
	mount "$ROOT_PART" /mnt
	if [[ -n $HOME_PART ]]; then
		mkfs.ext4 -F -L home "$HOME_PART"
		mount --mkdir "$HOME_PART" /mnt/home
	fi
}

format_and_mount() {
	info "Formatting and mounting"
	if [[ $FORMAT_ESP == yes ]]; then
		mkfs.vfat -F32 -n efi "$ESP_PART"
	fi
	case $FS in
	btrfs) setup_btrfs ;;
	ext4) setup_ext4 ;;
	esac
	mount --mkdir -o "$ESP_OPTS" "$ESP_PART" /mnt/boot

	local free_mib
	free_mib=$(df --output=avail -BM /mnt/boot | tail -n 1 | tr -dc '0-9')
	if ((free_mib < 250)); then
		warn "Only ${free_mib} MiB free on the ESP; the kernel and initramfs may not fit."
		ask_yn "Continue anyway?" n || die "Aborted. Free up space on the ESP or enlarge it."
	fi
}

install_base() {
	info "Installing the base system (pacstrap)"
	local pkgs=(
		base base-devel "$KERNEL" "${KERNEL}-headers"
		linux-firmware amd-ucode networkmanager nano man-db man-pages
	)
	if [[ $FS == btrfs ]]; then pkgs+=(btrfs-progs); fi
	pacstrap -K /mnt "${pkgs[@]}"
}

verify_fstab() {
	local fstab=/mnt/etc/fstab root_uuid esp_uuid root_opts esp_opts home_opts
	root_uuid=$(blkid -s UUID -o value "$ROOT_PART")
	esp_uuid=$(blkid -s UUID -o value "$ESP_PART")
	root_opts=$(awk -v u="UUID=$root_uuid" '$1 == u && $2 == "/" {print $4}' "$fstab")
	esp_opts=$(awk -v u="UUID=$esp_uuid" '$1 == u && $2 == "/boot" {print $4}' "$fstab")

	[[ -n $root_opts ]] || die "fstab: no entry for /"
	[[ -n $esp_opts ]] || die "fstab: no entry for /boot"
	[[ ,$esp_opts, == *,fmask=0077,* && ,$esp_opts, == *,dmask=0077,* ]] ||
		die "fstab: /boot lacks fmask/dmask=0077 (world-readable ESP)"

	if [[ $FS == btrfs ]]; then
		[[ ,$root_opts, == *,subvol=/@,* ]] || die "fstab: / is not subvol=/@"
		[[ ,$root_opts, == *,compress=zstd:3,* ]] || die "fstab: / lacks compress=zstd:3"
		home_opts=$(awk '$2 == "/home" {print $4}' "$fstab")
		[[ ,$home_opts, == *,subvol=/@home,* ]] || die "fstab: /home is not subvol=/@home"
		! grep -q 'subvolid=' "$fstab" || die "fstab: subvolid= was not stripped"
	fi
	ok "fstab looks correct"
}

generate_fstab() {
	info "Generating and verifying fstab"
	genfstab -U /mnt >/mnt/etc/fstab
	if [[ $FS == btrfs ]]; then
		sed -i -E 's/subvolid=[0-9]+,//g' /mnt/etc/fstab
	fi
	verify_fstab
}

run_chroot_stage() {
	info "Configuring the new system (arch-chroot)"
	local v
	install -Dm755 "$SCRIPT_PATH" /mnt/root/arch-setup.sh
	{
		for v in ROOT_PART FS KERNEL LOCALE_MODE HOSTNAME_VALUE USERNAME; do
			printf '%s=%q\n' "$v" "${!v}"
		done
	} >"/mnt${STATE_FILE}"
	chmod 600 "/mnt${STATE_FILE}"

	arch-chroot /mnt /root/arch-setup.sh chroot

	rm -f /mnt/root/arch-setup.sh "/mnt${STATE_FILE}"
	printf '%s\n' "root:${ROOT_PW}" "${USERNAME}:${USER_PW}" | arch-chroot /mnt chpasswd
	ok "Passwords set"
}

cmd_install() {
	((EUID == 0)) || die "Run this stage as root."
	[[ -d /run/archiso ]] || die "The install stage must run from the Arch live ISO."
	[[ -d /sys/firmware/efi/efivars ]] || die "Not booted in UEFI mode."
	check_network "Connect first, e.g.: iwctl station wlan0 connect \"SSID\""
	if mountpoint -q /mnt; then die "/mnt is already mounted. Run: umount -R /mnt"; fi
	timedatectl set-ntp true

	CONFIRMED=no
	while [[ $CONFIRMED != yes ]]; do
		collect_install_config
		confirm_install
	done
	format_and_mount
	install_base
	generate_fstab
	run_chroot_stage

	info "Finishing"
	umount -R /mnt
	cat <<EOF

${C_GREEN}${C_BOLD}Base system installed.${C_OFF}
After the reboot log in as ${C_BOLD}${USERNAME}${C_OFF}, connect to Wi-Fi if needed (nmtui), then run:

    ./arch-setup.sh post

EOF
	if ask_yn "Reboot now?" y; then reboot; fi
}

# --------------------------------------------------------------------------- #
# Stage 1b: inside arch-chroot (internal)
# --------------------------------------------------------------------------- #

chroot_time() {
	info "Time"
	ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
	hwclock --systohc
}

chroot_locale() {
	info "Localization ($LOCALE_MODE)"
	local l lang
	if [[ $LOCALE_MODE == auto ]]; then
		sed -i -E 's/^#\s*((en_US|en_DK|uk_UA)\.UTF-8 UTF-8)/\1/' /etc/locale.gen
		for l in en_US en_DK uk_UA; do
			grep -q "^${l}\.UTF-8 UTF-8" /etc/locale.gen || die "${l}.UTF-8 missing in /etc/locale.gen"
		done
		locale-gen
		cat >/etc/locale.conf <<'EOF'
LANG=en_US.UTF-8
LC_TIME=en_DK.UTF-8
LC_MONETARY=uk_UA.UTF-8
LC_NUMERIC=uk_UA.UTF-8
LC_MEASUREMENT=uk_UA.UTF-8
LC_PAPER=uk_UA.UTF-8
EOF
	else
		nano /etc/locale.gen
		locale-gen
		while true; do
			ask_input lang "LANG value" "en_US.UTF-8"
			if grep -qixF "${lang/UTF-8/utf8}" < <(locale -a); then break; fi
			warn "'$lang' was not generated; uncomment it in /etc/locale.gen first (run nano in another TTY)."
		done
		echo "LANG=${lang}" >/etc/locale.conf
	fi
}

chroot_initramfs() {
	info "Initramfs"
	if ! grep -q '^# arch-setup' /etc/mkinitcpio.conf; then
		cat >>/etc/mkinitcpio.conf <<'EOF'

COMPRESSION="lz4"
COMPRESSION_OPTIONS=(-9)
EOF
	fi
	if [[ $FS == btrfs ]]; then
		sed -i '/^HOOKS=/ s/ fsck//' /etc/mkinitcpio.conf
		! grep -qE '^HOOKS=.*\bfsck\b' /etc/mkinitcpio.conf || die "Could not remove the fsck hook"
	fi
	mkinitcpio -P
}

chroot_users() {
	info "Users"
	printf '%%wheel ALL=(ALL:ALL) ALL\n' >/etc/sudoers.d/10-wheel
	chmod 440 /etc/sudoers.d/10-wheel
	visudo -cf /etc/sudoers.d/10-wheel >/dev/null
	useradd -m -G wheel -s /bin/bash "$USERNAME"
	install -o "$USERNAME" -g "$USERNAME" -m 755 "$SCRIPT_PATH" "/home/${USERNAME}/arch-setup.sh"
}

chroot_bootloader() {
	info "Bootloader (systemd-boot)"
	[[ -f /boot/vmlinuz-$KERNEL ]] || die "/boot/vmlinuz-$KERNEL not found: is the ESP mounted at /boot?"
	bootctl install
	systemctl enable systemd-boot-update.service

	printf 'default arch.conf\ntimeout 5\n' >/boot/loader/loader.conf

	local uuid options title initrds=''
	uuid=$(blkid -s UUID -o value "$ROOT_PART")
	options="root=UUID=${uuid} rw zswap.enabled=0"
	if [[ $FS == btrfs ]]; then
		options="root=UUID=${uuid} rootflags=subvol=@ rw zswap.enabled=0"
	fi
	title="Arch Linux"
	if [[ $KERNEL == linux-zen ]]; then title="Arch Linux (Zen)"; fi

	if ! grep -qE '^HOOKS=.*\bmicrocode\b' /etc/mkinitcpio.conf; then
		[[ -f /boot/amd-ucode.img ]] || die "/boot/amd-ucode.img not found"
		initrds+="initrd  /amd-ucode.img"$'\n'
	fi
	initrds+="initrd  /initramfs-${KERNEL}.img"

	cat >/boot/loader/entries/arch.conf <<EOF
title   ${title}
linux   /vmlinuz-${KERNEL}
${initrds}
options ${options}
EOF
}

cmd_chroot() {
	((EUID == 0)) || die "Internal stage, run via: ./arch-setup.sh install"
	[[ -f $STATE_FILE ]] || die "State file $STATE_FILE not found."
	# shellcheck disable=SC1090
	source "$STATE_FILE"

	chroot_time
	chroot_locale
	info "Hostname"
	echo "$HOSTNAME_VALUE" >/etc/hostname
	chroot_initramfs
	chroot_users
	chroot_bootloader
	info "NetworkManager"
	systemctl enable NetworkManager.service
}

# --------------------------------------------------------------------------- #
# Stage 2: post-install
# --------------------------------------------------------------------------- #

collect_post_config() {
	FS=$(findmnt -no FSTYPE /)

	info "Choices"
	ask_choice GPU "GPU driver:" nvidia amd intel
	ask_choice DE "Desktop environment:" kde gnome

	local bt_default=n
	if compgen -G '/sys/class/bluetooth/hci*' >/dev/null; then
		bt_default=y
		echo "Bluetooth adapter detected."
	fi
	WANT_BLUETOOTH=0
	if ask_yn "Install Bluetooth support?" "$bt_default"; then WANT_BLUETOOTH=1; fi

	WANT_REFLECTOR=0
	if ask_yn "Refresh mirrors with reflector (Germany, Ukraine, Poland)?" n; then WANT_REFLECTOR=1; fi

	WANT_SNAPPER=0
	if [[ $FS == btrfs ]]; then
		if findmnt -rn /var/log >/dev/null && findmnt -rn /var/cache/pacman/pkg >/dev/null; then
			if ask_yn "Install and configure Snapper?" n; then WANT_SNAPPER=1; fi
		else
			echo "Snapper skipped: /var/log and /var/cache/pacman/pkg are not separate subvolumes."
		fi
	fi
}

step_pacman() {
	info "Pacman: multilib, colors, parallel downloads"
	as_root sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
	as_root sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
	as_root sed -i 's/^#Color$/Color/' /etc/pacman.conf
	grep -q '^\[multilib\]' /etc/pacman.conf || die "multilib could not be enabled"

	if ((WANT_REFLECTOR)); then
		pac reflector
		as_root reflector --protocol https --country Germany,Ukraine,Poland \
			--age 6 --sort rate --save /etc/pacman.d/mirrorlist
	fi
	as_root pacman -Syu
}

step_gpu() {
	info "GPU drivers ($GPU)"
	pac "${GPU_COMMON_PKGS[@]}"
	case $GPU in
	nvidia)
		local driver=nvidia-open
		if [[ $(uname -r) != *-arch* ]]; then driver=nvidia-open-dkms; fi
		pac "$driver" nvidia-utils lib32-nvidia-utils nvidia-settings libva-nvidia-driver
		;;
	amd)
		pac mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
		;;
	intel)
		pac mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver
		;;
	esac
}

step_fonts_sound() {
	info "Fonts and sound"
	pac "${FONT_PKGS[@]}"
	pac "${SOUND_PKGS[@]}"
}

remove_gnome_apps() {
	local installed=() p
	for p in "${GNOME_REMOVE[@]}"; do
		if pacman -Qq "$p" &>/dev/null; then installed+=("$p"); fi
	done
	if ((${#installed[@]})); then
		as_root pacman -Rns "${installed[@]}" || warn "GNOME apps were not removed, continuing."
	fi
}

step_desktop() {
	info "Desktop environment ($DE)"
	case $DE in
	kde)
		pac "${KDE_PKGS[@]}" "${KDE_APPS[@]}"
		as_root systemctl enable plasmalogin.service
		;;
	gnome)
		pac gnome
		as_root systemctl enable gdm.service
		remove_gnome_apps
		;;
	esac
}

step_programs() {
	info "Programs"
	pac "${BASIC_PKGS[@]}"
	if [[ $DE == gnome ]]; then pac "${GNOME_ONLY_PKGS[@]}"; fi
	pac steam gamemode lib32-gamemode
	as_root usermod -aG gamemode "$USER"
}

step_gnome_defaults() {
	[[ $DE == gnome ]] || return 0
	info "GNOME defaults"
	as_root install -d /etc/dconf/profile /etc/dconf/db/local.d
	printf 'user-db:user\nsystem-db:local\n' | write_root /etc/dconf/profile/user
	printf '[org/gnome/settings-daemon/plugins/media-keys]\nvolume-step=2\n' |
		write_root /etc/dconf/db/local.d/00-arch-setup
	as_root dconf update
}

step_services() {
	info "Firewall, power profiles, DNS cache, package cache"
	pac ufw
	as_root systemctl enable --now ufw.service
	as_root ufw default deny incoming
	as_root ufw default allow outgoing
	as_root ufw --force enable

	pac power-profiles-daemon
	as_root systemctl enable --now power-profiles-daemon.service

	if ((WANT_BLUETOOTH)); then
		pac bluez bluez-utils
		if [[ $DE == kde ]]; then pac bluedevil; fi
		as_root systemctl enable --now bluetooth.service
	fi

	write_root /etc/NetworkManager/conf.d/dns.conf <<'EOF'
[main]
dns=dnsmasq
EOF
	pac dnsmasq
	as_root nmcli general reload

	pac pacman-contrib
	as_root systemctl enable --now paccache.timer

	if [[ $FS == ext4 ]]; then
		as_root systemctl enable --now fstrim.timer
	fi
}

step_zram() {
	info "Swap on zram"
	pac zram-generator
	write_root /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = lz4
swap-priority = 100
EOF
	write_root /etc/sysctl.d/99-zram.conf <<'EOF'
vm.swappiness=180
vm.page-cluster=0
EOF
	local entry=/boot/loader/entries/arch.conf
	as_root test -f "$entry" || die "$entry not found"
	as_root sed -i '/^options/ { /zswap\.enabled=0/! s/$/ zswap.enabled=0/ }' "$entry"
	as_root grep -q 'zswap\.enabled=0' "$entry" || die "zswap.enabled=0 was not added to $entry"
	as_root systemctl daemon-reload
}

step_shell() {
	info "Shell: zsh"
	pac zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting

	local tmp custom=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
	if [[ ! -d $HOME/.oh-my-zsh ]]; then
		tmp=$(mktemp)
		curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$tmp"
		RUNZSH=no CHSH=no sh "$tmp"
		rm -f "$tmp"
	fi
	if [[ ! -d $custom/themes/powerlevel10k ]]; then
		git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$custom/themes/powerlevel10k"
	fi

	if ! grep -q 'powerlevel10k' "$HOME/.zshrc"; then
		# shellcheck disable=SC2016
		sed -i 's#^ZSH_THEME=.*#if [ "$TERM" = "linux" ]; then\n  ZSH_THEME="robbyrussell"\nelse\n  ZSH_THEME="powerlevel10k/powerlevel10k"\nfi#' "$HOME/.zshrc"
		grep -q 'powerlevel10k' "$HOME/.zshrc" || die "Could not set ZSH_THEME in ~/.zshrc"
	fi
	if ! grep -q '^# arch-setup plugins' "$HOME/.zshrc"; then
		cat >>"$HOME/.zshrc" <<'EOF'

source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF
	fi

	touch "$HOME/.nanorc"
	grep -qxF 'include /usr/share/nano/*.nanorc' "$HOME/.nanorc" ||
		echo 'include /usr/share/nano/*.nanorc' >>"$HOME/.nanorc"

	as_root chsh -s /usr/bin/zsh "$USER"
}

step_snapper() {
	((WANT_SNAPPER)) || return 0
	info "Snapper"
	if findmnt -rn /.snapshots >/dev/null; then
		warn "/.snapshots is already mounted, skipping Snapper setup."
		return 0
	fi
	pac snapper snap-pac

	local src dev uuid tmp
	src=$(findmnt -no SOURCE /)
	dev=${src%%\[*}
	uuid=$(as_root blkid -s UUID -o value "$dev")

	as_root snapper -c root create-config /
	as_root btrfs subvolume delete /.snapshots

	tmp=$(mktemp -d)
	as_root mount -o subvolid=5 "$dev" "$tmp"
	as_root btrfs subvolume create "$tmp/@snapshots"
	as_root umount "$tmp"
	rmdir "$tmp"

	as_root mkdir /.snapshots
	as_root mount -o "${BTRFS_OPTS},subvol=@snapshots" "$dev" /.snapshots
	as_root chmod 750 /.snapshots
	as_root chown :wheel /.snapshots
	echo "UUID=${uuid} /.snapshots btrfs ${BTRFS_OPTS},subvol=@snapshots 0 0" |
		as_root tee -a /etc/fstab >/dev/null

	as_root snapper -c root set-config \
		"TIMELINE_CREATE=yes" "TIMELINE_CLEANUP=yes" \
		"TIMELINE_LIMIT_HOURLY=5" "TIMELINE_LIMIT_DAILY=7" \
		"TIMELINE_LIMIT_WEEKLY=0" "TIMELINE_LIMIT_MONTHLY=0" "TIMELINE_LIMIT_YEARLY=0"
	as_root systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
}

step_finalize() {
	info "Hardening the boot menu"
	if ! as_root grep -q '^editor' /boot/loader/loader.conf; then
		echo 'editor no' | as_root tee -a /boot/loader/loader.conf >/dev/null
	fi
}

cmd_post() {
	((EUID != 0)) || die "Run the post stage as your regular user, not root."
	sudo -v
	as_root test -f /boot/loader/entries/arch.conf ||
		die "/boot/loader/entries/arch.conf not found: was stage 1 completed?"
	check_network "Connect with: nmtui"

	collect_post_config
	step_pacman
	step_gpu
	step_fonts_sound
	step_desktop
	step_programs
	step_gnome_defaults
	step_services
	step_zram
	step_shell
	step_snapper
	step_finalize

	cat <<EOF

${C_GREEN}${C_BOLD}Post-install finished.${C_OFF}
A reboot is needed to start the desktop and activate zram and the new kernel parameters.
After rebooting, run:  ./arch-setup.sh check
EOF
	if [[ $DE == kde ]]; then
		echo "KDE: create the 'kdewallet' wallet (Blowfish, same password as your login) in kwalletmanager."
	fi
	if ask_yn "Reboot now?" y; then sudo reboot; fi
}

# --------------------------------------------------------------------------- #
# Stage 3: check
# --------------------------------------------------------------------------- #

PASS=0
FAIL=0
WARN=0
SKIP=0

report() {
	local status=$1 name=$2 detail=${3:-}
	case $status in
	pass)
		printf ' %s✔%s %-26s %s\n' "$C_GREEN" "$C_OFF" "$name" "$detail"
		PASS=$((PASS + 1))
		;;
	fail)
		printf ' %s✘%s %-26s %s\n' "$C_RED" "$C_OFF" "$name" "$detail"
		FAIL=$((FAIL + 1))
		;;
	warn)
		printf ' %s!%s %-26s %s\n' "$C_YELLOW" "$C_OFF" "$name" "$detail"
		WARN=$((WARN + 1))
		;;
	skip)
		printf ' %s-%s %-26s %s\n' "$C_BLUE" "$C_OFF" "$name" "$detail"
		SKIP=$((SKIP + 1))
		;;
	esac
}

check_nvidia() {
	local params modeset
	if ! grep -q '^nvidia ' /proc/modules; then
		report skip "NVIDIA" "driver not loaded"
		return 0
	fi
	params=$(as_root cat /proc/driver/nvidia/params)
	if [[ -n $params ]]; then
		report pass "NVIDIA params" "readable"
	else
		report fail "NVIDIA params" "/proc/driver/nvidia/params is empty"
	fi
	modeset=$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || true)
	if [[ $modeset == Y ]]; then
		report pass "NVIDIA DRM modeset" "Y"
	else
		report fail "NVIDIA DRM modeset" "expected Y, got '${modeset:-n/a}'"
	fi
	if [[ $params == *"UseKernelSuspendNotifiers: 1"* ]]; then
		report pass "NVIDIA suspend path" "UseKernelSuspendNotifiers: 1"
	else
		report warn "NVIDIA suspend path" "not 1 (needs driver 595+ with open modules)"
	fi
}

check_system() {
	local swaps zswap boot_status boot_list opts ntp
	swaps=$(swapon --show --noheadings || true)
	if [[ $swaps == */dev/zram0* ]]; then
		report pass "Swap (zram)" "/dev/zram0 active"
	else
		report fail "Swap (zram)" "/dev/zram0 not active"
	fi

	zswap=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo n/a)
	if [[ $zswap == N ]]; then
		report pass "zswap" "disabled"
	else
		report fail "zswap" "enabled ($zswap); add zswap.enabled=0 to arch.conf options"
	fi

	boot_status=$(as_root bootctl status 2>&1 || true)
	if [[ $boot_status == *systemd-boot* ]]; then
		report pass "Bootloader" "systemd-boot installed"
	else
		report fail "Bootloader" "systemd-boot not detected"
	fi
	boot_list=$(as_root bootctl list 2>&1 || true)
	if [[ $boot_list == *Windows* ]]; then
		report pass "Windows boot entry" "listed"
	else
		report warn "Windows boot entry" "not listed (fine if Windows is not installed)"
	fi

	opts=$(findmnt -no OPTIONS /)
	if [[ $(findmnt -no FSTYPE /) == btrfs ]]; then
		if [[ ,$opts, == *,compress=zstd:3,* && ,$opts, == *,subvol=/@,* ]]; then
			report pass "Filesystem" "btrfs, compress=zstd:3, subvol=/@"
		else
			report fail "Filesystem" "unexpected options: $opts"
		fi
	else
		report pass "Filesystem" "$(findmnt -no FSTYPE /)"
	fi

	ntp=$(timedatectl show -p NTPSynchronized --value)
	if [[ $ntp == yes ]]; then
		report pass "Time sync" "clock synchronized"
	else
		report fail "Time sync" "NTPSynchronized=$ntp"
	fi
}

check_services() {
	local u dm_found=0
	for u in plasmalogin gdm; do
		if systemctl is-enabled --quiet "$u.service" 2>/dev/null; then
			report pass "Display manager" "$u enabled"
			dm_found=1
		fi
	done
	if ((! dm_found)); then report fail "Display manager" "none enabled"; fi

	if [[ $(as_root ufw status 2>/dev/null) == *"Status: active"* ]]; then
		report pass "Firewall (ufw)" "active"
	else
		report fail "Firewall (ufw)" "not active"
	fi
	if systemctl is-enabled --quiet paccache.timer; then
		report pass "paccache.timer" "enabled"
	else
		report fail "paccache.timer" "not enabled"
	fi
	if systemctl is-active --quiet power-profiles-daemon.service; then
		report pass "power-profiles-daemon" "active"
	else
		report fail "power-profiles-daemon" "not active"
	fi
	if grep -q '^\[multilib\]' /etc/pacman.conf; then
		report pass "multilib" "enabled"
	else
		report fail "multilib" "disabled"
	fi
	if [[ $(getent passwd "$USER" | cut -d: -f7) == */zsh ]]; then
		report pass "Login shell" "zsh"
	else
		report warn "Login shell" "not zsh"
	fi
}

check_kwallet() {
	[[ ${XDG_CURRENT_DESKTOP:-} == *KDE* ]] || return 0
	if ! command -v qdbus6 >/dev/null; then
		report skip "KWallet" "qdbus6 missing (pacman -S qt6-tools)"
		return 0
	fi
	local out
	out=$(qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.isOpen kdewallet 2>/dev/null || true)
	if [[ $out == true ]]; then
		report pass "KWallet" "kdewallet is open"
	else
		report warn "KWallet" "create 'kdewallet' (Blowfish, login password) in kwalletmanager"
	fi
}

cmd_check() {
	((EUID != 0)) || die "Run the check stage as your regular user."
	sudo -v
	info "Checking the system"
	check_nvidia
	check_system
	check_services
	check_kwallet
	printf '\n%d passed, %d failed, %d warnings, %d skipped\n' "$PASS" "$FAIL" "$WARN" "$SKIP"
	((FAIL == 0))
}

# --------------------------------------------------------------------------- #

usage() {
	sed -n '2,10p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'
}

main() {
	local mode=${1:-auto}
	if [[ $mode == auto ]]; then
		if [[ -d /run/archiso ]]; then mode=install; else mode=post; fi
	fi
	case $mode in
	install) cmd_install ;;
	chroot) cmd_chroot ;;
	post) cmd_post ;;
	check) cmd_check ;;
	-h | --help | help) usage ;;
	*)
		usage
		exit 1
		;;
	esac
}

main "$@"
