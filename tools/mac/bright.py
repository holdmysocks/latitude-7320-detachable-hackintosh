#!/usr/bin/env python3
"""bright.py [get | set <0..1>]  - read or set the built-in display brightness through DisplayServices."""
import ctypes, sys
cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
ds = ctypes.CDLL('/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices')
cg.CGMainDisplayID.restype = ctypes.c_uint32
d = cg.CGMainDisplayID()
ds.DisplayServicesGetBrightness.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_float)]
ds.DisplayServicesSetBrightness.argtypes = [ctypes.c_uint32, ctypes.c_float]
def get():
    v = ctypes.c_float(-1); r = ds.DisplayServicesGetBrightness(d, ctypes.byref(v)); return r, v.value
if len(sys.argv) > 2 and sys.argv[1] == 'set':
    r = ds.DisplayServicesSetBrightness(d, float(sys.argv[2])); print("set rc", r)
print("display %#x get rc/value: %s" % (d, get()))
