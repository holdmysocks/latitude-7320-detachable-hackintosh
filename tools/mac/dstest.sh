#!/bin/sh
# dstest.sh <tag> [seconds off]  -  display sleep/wake test with a log that survives a hard reset.
# Writes $DSTEST_LOGS (default ~/dstest-logs)/durable-<time>-<tag>.log; a line starting T2 means the machine survived.
# log stream block-buffers into a pipe, so it runs under script(1) (a pty) to get every line out at once.
HERE=$(cd "$(dirname "$0")" && pwd)
D=${DSTEST_LOGS:-$HOME/dstest-logs}; mkdir -p "$D"; F=$D/durable-$(date +%H%M%S)-$1.log
OFF=${2:-10}
python3 "$HERE/ptylog.py" $F 'process == "kernel"' &
LP=$!
( while :; do sync; sleep 0.3; done ) & SP=$!
( i=0; while :; do echo "tick $(date +%T)" >> $F; sleep 1; done ) & TP=$!
sleep 3; echo "T0 $(date +%T) displaysleepnow" >> $F; sync; pmset displaysleepnow
sleep $OFF; echo "T1 $(date +%T) wake request" >> $F; sync; caffeinate -u -t 3
sleep 6; echo "T2 $(date +%T) after wake" >> $F; sync
kill $SP $TP $LP; pkill -f "log stream --style compact"; echo $F
