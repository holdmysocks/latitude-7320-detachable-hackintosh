#!/bin/sh
# Lid helper for a machine with system sleep disabled: display off when the lid closes, on when it opens.
prev=No
while :; do
  cur=$(ioreg -rc IOPMrootDomain -d1 | awk -F'= ' '/"AppleClamshellState"/{print $2}')
  if [ "$cur" != "$prev" ]; then
    if [ "$cur" = Yes ]; then pmset displaysleepnow; else caffeinate -u -t 2; fi
    echo "$(date '+%H:%M:%S') lid closed=$cur"
    prev=$cur
  fi
  sleep 1
done
