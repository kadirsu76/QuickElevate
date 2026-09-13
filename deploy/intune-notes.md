# Intune Deployment Notes

## 1) Package Upload

- Upload `dist/QuickElevate-<version>.pkg` as a macOS PKG app.
- Assign as `Required` to target device groups.

## 2) Dock Pin (Recommended)

- Prefer deploying `deploy/QuickElevate-Dock.mobileconfig` as a custom macOS profile.
- This is more reliable than post-install scripts for Dock pinning.
- Use `deploy/pin-to-dock.sh` only as fallback.

## 3) Notification Approval

- Deploy `deploy/QuickElevate-Notifications.mobileconfig` to pre-approve app notifications.

## 4) Health Check / Remediation

- Use `deploy/intune-remediation.sh` as detection script.
- Exit code `0` means healthy.
- Exit code `1` means remediation required.

## 5) Uninstall

- If you need explicit cleanup, run `deploy/intune-uninstall.sh` as root.

## 6) Operational Notes

- Helper service label: `com.quickelevate.helper`
- App path: `/Applications/QuickElevate.app`
- Socket path: `/var/run/quickelevate/quickelevate.sock`
