#!/usr/bin/env python3
"""Run `log stream` on a pty (so it is line-buffered) and append its output to a file, fsync'ing every chunk."""
import os, pty, sys
out = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
pid, fd = pty.fork()
if pid == 0:
    os.execv('/usr/bin/log', ['log', 'stream', '--style', 'compact', '--predicate', sys.argv[2]])
while True:
    try:
        data = os.read(fd, 65536)
    except OSError:
        break
    if not data:
        break
    os.write(out, data.replace(b'\r\n', b'\n'))
    os.fsync(out)
