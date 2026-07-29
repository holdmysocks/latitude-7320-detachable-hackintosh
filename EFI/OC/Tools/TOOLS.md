# Tools

`OpenShell.efi` from the OpenCore 1.0.7 RELEASE archive. Not committed —
[`tools/fetch-components.ps1`](../../../tools/fetch-components.ps1) places it
here.

It is enabled in `config.plist` with `Auxiliary = true`, so it only shows in
the picker after pressing **Space**.

Worth keeping. When a graphics experiment leaves the machine unbootable, a
UEFI shell is the fastest way to inspect the ESP without going back to Windows
and mounting it — see
[`../../../docs/05-post-install.md`](../../../docs/05-post-install.md#96-keep-the-usb-as-a-rescue-device).
