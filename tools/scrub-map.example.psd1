# scrub-map.example.psd1
#
# Copy to scrub-map.local.psd1 (gitignored) and replace the left-hand values
# with the real ones from your own machine. scrub.ps1 reads the local copy.
#
# Keys are the literal strings to find, values are what to write instead.
# Where a length carries meaning - a serial embedded in a hex blob, a MAC in
# base64 - keep the replacement the same length so the dump stays structurally
# faithful to what the machine actually printed.
#
# Find your own values with:
#     .\scrub.ps1 -Path ..\research\data -Recurse -Check
# which reports identifier-shaped strings without needing a map.

@{
    # --- SMBIOS / platform identity -------------------------------------
    'YOUR-MAC-SERIAL'          = 'CHANGE-ME-SERIAL'
    'YOUR-MLB-BOARD-SERIAL'    = 'CHANGE-ME-MLB'
    'YOUR-SYSTEM-UUID'         = '00000000-0000-0000-0000-000000000000'
    'YOUR-PLATFORM-UUID'       = '00000000-0000-0000-0000-000000000000'

    # The serial also appears hex-encoded inside the ioreg "serial-number"
    # blob. Same string, 2 hex chars per character, lower case.
    'YOUR-SERIAL-AS-HEX'       = '585858585858585858585858'   # 'XXXX...'

    # --- MAC addresses ---------------------------------------------------
    # ROM in config.plist is base64; ioreg prints MACs as bare hex.
    'YOUR-ROM-BASE64'          = 'ESIzRFVm'                   # 11:22:33:44:55:66
    'YOUR-WIFI-MAC-HEX'        = '112233445566'
    'YOUR-ETHERNET-MAC-HEX'    = '112233445566'

    # --- account names ---------------------------------------------------
    'YOUR-FULL-NAME'           = 'Redacted User'
    'YOUR-SHORT-USERNAME'      = 'user'

    # --- serials of attached hardware ------------------------------------
    # ioreg reports the NVMe serial, and the serial of every USB device that
    # happened to be plugged in when you captured. Easy to forget.
    'YOUR-NVME-SERIAL'         = 'XXXXXXXXXXXXXXXXX'
    'YOUR-USB-DEVICE-SERIAL'   = 'XXXXXXXX'
}
