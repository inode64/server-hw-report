#!/bin/bash
set -euo pipefail

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

grub-install --target=x86_64-efi --efi-directory=/efi --removable

echo "disks detected: ${disks[*]}"

for disk in "${disks[@]}"; do
	echo "Creating partitions on $disk..."
	efibootmgr -c -D -L "Gentoo ($disk)" -d $disk -p1 -l /efi/gentoo/grubx64.efi
done

