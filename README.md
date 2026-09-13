# QuickElevate

> **Alpha / not for production:** the current macOS helper still contains the original local-only grant path while the private Azure authorization gate is being implemented. Do not deploy the current package broadly. Production requires a backend-signed, single-use grant before the helper will elevate any user.

QuickElevate, macOS'ta kullaniciya Touch ID/parola onayi ile kisa sureli gecici admin yetkisi vermek icin tasarlanmis istemci + root helper cozumudur. Hedef mimaride yeni yetki talepleri private Azure backend tarafindan PIM grup uyeligiyle onaylanir.

## Ozellikler

- Dock uygulamasinda "60 sn Yetki Iste" aksiyonu.
- LocalAuthentication ile Touch ID/parola zorunlulugu.
- Root helper ile local `admin` grubuna gecici ekleme.
- Dock badge'de saniye bazli geri sayim (`60..0`).
- Sure sonunda otomatik revoke.
- Uygulama kapansa bile revoke zamanlayicisi helper tarafinda devam eder.

## Mimari

- `QuickElevateApp`: pencere acmadan Dock davranisi sunan AppKit istemcisi.
- `QuickElevateHelper`: root LaunchDaemon.
- `QuickElevateShared`: protokol ve socket transport.
- IPC: `/var/run/quickelevate/quickelevate.sock`.
- Hedef backend: `.NET 8 Azure Function`, Private Endpoint, Easy Auth, Managed Identity, Microsoft Graph ve Key Vault imzali grant.

Mimari ayrintilari icin `docs/architecture.md`, riskler icin `docs/threat-model.md` dosyalarina bakin.

## Private Azure Backend

Hedef backend `.NET 8 Azure Function` olarak `Backend/QuickElevate.Api` altindadir. Bicep altyapisi `Infrastructure/azure/main.bicep` dosyasinda bulunur.

`pimGroupObjectId` Azure deployment'in zorunlu parametresidir. Bu deger backend tarafinda tutulur; macOS istemcisi secemez veya degistiremez.

GitHub remote olusturulduktan sonra bu README'ye derlenmis ARM template'i kullanan `Deploy to Azure` butonu eklenecektir. Bicep/ARM deploy, Entra app registration, Graph admin consent ve Conditional Access islemlerini tamamen otomatiklestirmez; bunlar tenant admin tarafindan tamamlanmalidir.

## Guvenlik Sertlestirmeleri

- Helper, soket istemcisinin `uid/gid/pid` bilgisini kernel'den alir.
- Yalniz aktif console user taleplerine izin verilir.
- Root caller reddedilir.
- Istemci proses yolu `/Applications/QuickElevate.app/Contents/MacOS/QuickElevateApp` ile eslesmelidir.
- Istemci kod imzasi, kurulu guvenilir ikilinin designated requirement'i ile dogrulanir.
- `request.user` alani peer uid ile birebir eslesmelidir.

## Build

```bash
swift build
swift build -c release
```

## Gelistirme Kurulumu

```bash
chmod +x deploy/install-helper.sh deploy/pin-to-dock.sh
./deploy/install-helper.sh
```

## PKG Uretimi

```bash
chmod +x deploy/build-pkg.sh deploy/notarize-pkg.sh deploy/pkg-scripts/preinstall deploy/pkg-scripts/postinstall
swift build -c release
./deploy/build-pkg.sh 0.1.0
```

Imzali paket icin:

```bash
export DEVELOPER_ID_INSTALLER="Developer ID Installer: COMPANY NAME (TEAMID)"
./deploy/build-pkg.sh 0.1.0
```

Notarization icin:

```bash
export NOTARY_PROFILE="quickelevate-notary"
./deploy/notarize-pkg.sh dist/QuickElevate-0.1.0.pkg
```

## Intune Dagitimi

- `dist/QuickElevate-<version>.pkg` dosyasini Intune macOS PKG app olarak yukleyin.
- Dock pin icin `deploy/QuickElevate-Dock.mobileconfig` profilini custom profile olarak dagitin.
- Bildirim izni icin `deploy/QuickElevate-Notifications.mobileconfig` profilini dagitin.
- `deploy/pin-to-dock.sh` scripti yalniz fallback amaclidir.
- Health kontrolu icin `deploy/intune-remediation.sh`, temiz uninstall icin `deploy/intune-uninstall.sh` kullanin.
- Ayrintili adimlar icin `deploy/intune-notes.md` dosyasina bakin.
- Private backend ayarlari icin `deploy/QuickElevate-Configuration.mobileconfig.example` dosyasini kullanin.
- VPN/GSA ve Azure kurulum adimlari icin `docs/intune-deployment.md` ve `Infrastructure/azure/README.md` dosyalarina bakin.

## Risk Notu

60 saniye kisa bir sure olsa da bu pencerede kullanici gercek local admin olur. Bu surede kalici sistem degisiklikleri yapilabilir. Bu nedenle endpoint hardening, audit ve izleme politikalari ile birlikte kullanilmalidir.
