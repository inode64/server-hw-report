#!/bin/bash
set -euo pipefail

if ! command -v parted &> /dev/null || ! command -v mdadm &> /dev/null; then
	echo "Require 'parted' and 'mdadm' installed."
	exit 1
fi

# Detect disk NVMe devices
disks=( $(lsblk -dpno NAME,TYPE | awk '$2 == "disk" && $1 ~ /nvme/ {print $1}'|sort) )

if [ "${#disks[@]}" -lt 2 ]; then
	# If no NVMe disks found, fallback to detecting regular disks
	disks=( "$(lsblk -dpno NAME,TYPE | awk '$2 == "disk" && $1 ~ /sd/ {print $1}')" )
	if [ "${#disks[@]}" -lt 2 ]; then
		echo "Require at least 2 NVMe disks for RAID configuration."
		exit 1
	fi
fi

echo "disks detected: ${disks[*]}"

for disk in "${disks[@]}"; do
	echo "Creating partitions on $disk..."

	parted -a optimal -s "$disk" mklabel gpt
	parted -a optimal -s "$disk" mkpart ESP fat32 0% 128MiB
	parted -a optimal -s "$disk" set 1 boot on
	parted -a optimal -s "$disk" mkpart primary 128MiB 100%
	parted -a optimal -s "$disk" set 2 raid on
done

sleep 2

efi_parts=()
raid_parts=()

for disk in "${disks[@]}"; do
	efi_parts+=("${disk}p1")
	raid_parts+=("${disk}p2")
done

echo "Creating RAID1 for EFI partitions..."
mdadm --create --verbose /dev/md0 --level=1 --raid-devices=${#efi_parts[@]} --metadata=0.90 --force --assume-clean "${efi_parts[@]}"

if [ "${#raid_parts[@]}" -eq 2 ]; then
	nivel=1
else
	nivel=5
fi

echo "Creating RAID${nivel} for data partitions..."
mdadm --create --verbose /dev/md1 --level=$nivel --raid-devices=${#raid_parts[@]} --metadata=1.2 --force --assume-clean "${raid_parts[@]}"

cat /proc/mdstat

pvcreate /dev/md1
vgcreate data /dev/md1
mkfs.fat -F 32 -n BOOT /dev/md0
lvcreate -L30G -nboot data
mkfs.ext4 -m0 -L boot /dev/data/boot
lvcreate -L32G -nswap data
mkswap -L swap /dev/data/swap
swapon /dev/data/swap

mkdir -p /mnt/disk
mount /dev/data/boot /mnt/disk

mkdir -p /mnt/disk/efi/
mount /dev/md0 /mnt/disk/efi/
