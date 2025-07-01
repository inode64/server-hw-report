#!/usr/bin/env bash
# anon-dmesg.sh
sed -i -E \
  -e 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/XX:XX:XX:XX:XX:XX/gi' \
  -e 's#https?://[^ ]+#https://REDACTED#g' \
  -e 's/(GPG_KEYS=)[^ ]+/\1<REDACTED>/' \
  -e 's/Serial Number: [^ ]+/Serial Number: <REDACTED>/' \
  -e 's/SerialNumber=[^ ]+/SerialNumber=<REDACTED>)/' \
  -e 's/Hostname set to <[^>]+>/Hostname set to <host.example>/' \
  -e 's/HostName=[^ ]+ /HostName=<host.example> /' \
  -e '/^Serial Number:/s/.*/Serial Number:                      <REDACTED>/' \
  -e '/systemd-gpt-auto-generator.*/d' \
  *.txt

rm ifconfig.txt 2>/dev/null
rm route.txt 2>/dev/null
rm route6.txt 2>/dev/null

