#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# clone-scrub.sh – Scrub a Gentoo installation before cloning it to a new host
# ---------------------------------------------------------------------------
# • Replaces the old hostname with the new one in common configuration files.
# • Removes host‑specific keys, logs, caches, etc.
# • Regenerates machine‑id and leaves hooks to rebuild host keys.
# ---------------------------------------------------------------------------
# Usage:
#   sudo ./clone-scrub.sh -d /mnt/disk -n NEW_HOSTNAME [-s]
#
# Options:
#   -d  Mount point of the Gentoo root to clean.
#   -n  New hostname (short name, no domain).
#   -s  Dry‑run – just print what would be done.
# ---------------------------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<USAGE >&2
Usage: $0 -d <mount_point> -n <new_hostname> [-s]
USAGE
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Parse arguments
# ---------------------------------------------------------------------------
disk=""
new_host=""
DRYRUN=0

while getopts "d:n:s" opt; do
  case $opt in
    d) disk=$OPTARG ;;
    n) new_host=$OPTARG ;;
    s) DRYRUN=1 ;;
    *) usage ;;
  esac
done

[[ -z $disk || -z $new_host ]] && usage
[[ -d $disk ]] || { echo "[ERROR] Path $disk does not exist" >&2; exit 1; }
[[ ${disk: -1} == "/" ]] && disk=${disk%/}

run() {
  if (( DRYRUN )); then
    echo "[DRY-RUN] $@"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# 2. Detect old hostname
# ---------------------------------------------------------------------------
if [ -e "$disk/etc/hostname" ]; then
  old_host=$(cat "$disk/etc/hostname" || true)
else
  old_host=$(awk -F= '/^hostname=/ {
        gsub(/"/,"", $2);          # remove quote characters
        print a[1];                   # output bare short hostname
        exit                          # only first match
      }' "$disk/etc/conf.d/hostname" 2>/dev/null || true)
fi

[[ -n $old_host ]] || { echo "[ERROR] Could not detect old hostname" >&2; exit 1; }

echo "Old hostname : $old_host"
echo "New hostname : $new_host"
[[ $DRYRUN -eq 1 ]] && echo "*** DRY-RUN MODE – no changes will be written ***"

# ---------------------------------------------------------------------------
# 3. Replace hostname in config files
# ---------------------------------------------------------------------------
readarray -t conf_files < <(cat <<EOF
etc/hosts
etc/monitrc
etc/exim/*.conf
etc/dovecot/*.conf
etc/conf.d/hostname
etc/hostname
etc/dhcp/dhclient.conf
etc/salt/minion_id
EOF
)

for pattern in "${conf_files[@]}"; do
  for f in $pattern; do
    [[ -f $disk/$f ]] || continue
    run sed -i "s:${old_host}:${new_host}:g" "$disk/$f"
  done
done

# ---------------------------------------------------------------------------
# 4. Directories to wipe (contents only)
# ---------------------------------------------------------------------------
readarray -t wipe_dirs < <(cat <<EOF
etc/cups/ppd
etc/cups/ssl
etc/libvirt/secrets
etc/lvm/archive
etc/lvm/backup
etc/monit.d
etc/monit.local
etc/salt/pki/minion
opt/LOG_imapsync
opt/awstats.tmp
run
tmp
var/account
var/bind/sec
var/cache/atop.d
var/cache/cups
var/cache/fontconfig
var/cache/genkernel
var/cache/libvirt/qemu/capabilities
var/cache/revdep-rebuild
var/cache/salt
var/cache/samba
var/db/webapps
var/dcc
var/lib/NetworkManager
var/lib/alsa
var/lib/backrest
var/lib/bacula
var/lib/bareos
var/lib/dhcp
var/lib/dovecot
var/lib/ebtables
var/lib/elasticsearch
var/lib/fail2ban
var/lib/freeipmi
var/lib/glusterd
var/lib/iptraf-ng
var/lib/kafka
var/lib/keydb
var/lib/libvirt/qemu
var/lib/misc
var/lib/mysql
var/lib/net-snmp
var/lib/nftables
var/lib/nut
var/lib/openvswitch
var/lib/pcp
var/lib/postgresql
var/lib/rabbitmq
var/lib/redis
var/lib/rspamd
var/lib/samba/private
var/lib/seedrng
var/lib/squid
var/lib/syslog-ng
var/lib/systemd
var/monit
var/nmbd
var/sieve-scripts
var/spool/backup/conf
var/spool/backup/critical
var/spool/backup/mysql
var/spool/dspam
var/spool/exim
var/spool/mail
var/svc.d
var/tmp
var/www
EOF
)

for d in "${wipe_dirs[@]}"; do
  [[ -d $disk/$d ]] || continue
  echo "Cleaning directory: ${d}/*"
  run rm -rf -- "$disk/$d"/*
  run rm -rf -- "$disk/$d"/.[!.]* "$disk/$d"/..?* || true
done

# ---------------------------------------------------------------------------
# 5. Individual files to remove
# ---------------------------------------------------------------------------
remove_files=(
  "etc/machine-id"
  "var/lib/systemd/random-seed"
  "var/lib/ntp/ntp.drift"
)
for f in "${remove_files[@]}"; do
  [[ -e $disk/$f ]] && run rm -f -- "$disk/$f"
done

# ---------------------------------------------------------------------------
# 6. Bulk find deletion (files only)
# ---------------------------------------------------------------------------
while read -r path; do
  [[ -d $path ]] || continue
  echo "Cleaning tree    : ${path}/ (files)"
  run find "$disk/$path" -mindepth 1 -type f -delete
done <<EOF
etc/apache2/vhosts.d
etc/openvpn/keys/${new_host}
etc/openvpn/keys/${old_host}
etc/php/*/fpm.d
etc/ssh/*{key,pub,old,crt,csr,ant,pem}
etc/udev/rules.d/*persistent-net.rules
var/bin/*.jnl
var/bin/named.log*
var/lib/libvirt
var/lib/nfs
var/lib/run
var/lib/samba
var/lib/unifi
var/log
var/spool/cups
EOF

# ---------------------------------------------------------------------------
# 7. Remove specific files in libvirt directories
# ---------------------------------------------------------------------------
run find "$disk/etc/libvirt/qemu" -mindepth 1 -type f ! -name 'default.xml' -delete 2>/dev/null || true
run find "$disk/etc/libvirt/storage" -mindepth 1 -type f ! -name 'default.xml' -delete 2>/dev/null || true

# ---------------------------------------------------------------------------
# 8. Regenerate machine‑id (real run only)
# ---------------------------------------------------------------------------
if (( DRYRUN == 0 )) && command -v systemd-machine-id-setup &>/dev/null; then
  echo "Regenerating machine-id in $disk"
  systemd-machine-id-setup --root="$disk"
fi

if (( DRYRUN == 0 )) && [[ -e $disk/etc/openvswitch/system-id.conf ]]; then
  echo "Regenerating Open vSwitch system-id"
  uuigen > "$disk/etc/openvswitch/system-id.conf"
fi

# ---------------------------------------------------------------------------
# 9. Empty files
# ---------------------------------------------------------------------------

readarray -t empty_file < <(cat <<EOF
var/db/ntp-kod
EOF
)

for d in "${empty_file[@]}"; do
  [[ -e $disk/$d ]] || continue
  echo "Empty file : ${d}"
  run echo "" > "$disk/$d"
done
