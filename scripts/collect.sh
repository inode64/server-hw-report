#!/bin/bash

printInfo() { printf "${COLOR_RESET-}[${COLOR_BGREEN-}INFO${COLOR_RESET-}] %s\n" "${@-}"; }

# Define terminal colors if the color option is enabled or in auto mode if STDOUT is attached to a TTY and the
# "NO_COLOR" variable is not set (https://no-color.org).
if [ -z "${NO_COLOR+x}" ] && [ -t 1 ]; then
    COLOR_RESET="$({ exists tput && tput sgr0; } 2>/dev/null || printf '\033[0m')"
    COLOR_BRED="$({ exists tput && tput bold && tput setaf 1; } 2>/dev/null || printf '\033[1;31m')"
    COLOR_BGREEN="$({ exists tput && tput bold && tput setaf 2; } 2>/dev/null || printf '\033[1;32m')"
    COLOR_BYELLOW="$({ exists tput && tput bold && tput setaf 3; } 2>/dev/null || printf '\033[1;33m')"
    COLOR_BCYAN="$({ exists tput && tput bold && tput setaf 6; } 2>/dev/null || printf '\033[1;36m')"
fi

dir=/var/log/machine/

mkdir -p ${dir}  &>/dev/null

printInfo "### Install applications"
apt-get install usbutils -y &>/dev/null
apt-get install freeipmi -y &>/dev/null
apt-get install hdparm -y &>/dev/null
apt-get install hwloc -y &>/dev/null

printInfo "### Hardware & Peripherals"
lsusb &>${dir}/lsusb.txt
lspci &>${dir}/lspci.txt
lsmod &>${dir}/lsmod.txt
hwloc-ls -v &>${dir}/hwloc.txt

printInfo "### System Base"
dmesg -t &>${dir}/dmesg.txt
dmidecode &>${dir}/dmidecode.txt
cp /proc/cpuinfo ${dir}/cpuinfo.txt
cp /proc/interrupts ${dir}/interrupts.txt
cp /proc/iomem ${dir}/iomem.txt
cp /proc/ioports ${dir}/ioports.txt
cp /proc/meminfo ${dir}/meminfo.txt

cat /sys/class/dmi/id/bios_date &>${dir}/bios_date.txt
cat /sys/class/dmi/id/bios_release &>${dir}/bios_release.txt
cat /sys/class/dmi/id/bios_version &>${dir}/bios_version.txt

printInfo "### Sensors"
sensors &>${dir}/sensors.txt
ipmi-sensors 2>/dev/null >${dir}/ipmi-sensors.txt

printInfo "### Disks"
for dev in /sys/block/*; do
    name="$(basename "${dev}")"
    if [ -e "${dev}/device" ]; then
        smartctl --xall /dev/${name} &>${dir}/${name}_smart.txt
        hdparm -tT /dev/${name} &>${dir}/${name}_speed.txt
    fi
done

printInfo "### Network"
ifconfig &>${dir}/ifconfig.txt
route -n &>${dir}/route.txt
route -n6 &>${dir}/route6.txt

for interface in /sys/class/net/*; do
    name="$(basename "${interface}")"
    if [ -e "${interface}/device" ]; then
        ethtool ${name} &>${dir}/${name}.txt
        ethtool -k ${name} &>${dir}/${name}_features.txt
        ethtool -i ${name} &>${dir}/${name}_info.txt
    fi
done

printInfo "### Test CPU"
stress-ng --cpu 0 --cpu-method all --timeout 5m --verify --metrics-brief --perf &>${dir}/stress_cpu.txt
