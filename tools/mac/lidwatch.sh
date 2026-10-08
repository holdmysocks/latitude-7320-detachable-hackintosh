#!/bin/sh
# lidwatch.sh - turn the display off when the lid closes.
#
# For a machine where system sleep is disabled (pmset disablesleep 1) because the firmware has no S3: macOS sees the
# lid close but does nothing, and the panel stays lit. This polls the lid state once a second and sleeps the display
# on close. Opening the lid wakes the display by itself; the caffeinate call only makes sure of it.
# The machine stays awake with the lid closed. Install as a login item with install-lidwatch.sh.
prev=No
while :; do
  cur=$(/usr/sbin/ioreg -rc IOPMrootDomain -d1 | /usr/bin/awk -F'= ' '/"AppleClamshellState"/{print $2}')
  if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then
    if [ "$cur" = Yes ]; then /usr/bin/pmset displaysleepnow; else /usr/bin/caffeinate -u -t 2; fi
    echo "$(/bin/date '+%Y-%m-%d %H:%M:%S') lid closed=$cur"
    prev=$cur
  fi
  /bin/sleep 1
done
