# l-portal hibernate analyse

Laatste update: 2026-06-22 20:10 CEST

Doel: hibernate op `l-portal` werkend krijgen met encrypted root via
Clevis/Tang en encrypted persistent swap via keyfile in `/persist`.

## Huidige conclusie

De storage/initrd kant werkt. De machine vindt `cryptswap`, ziet de resume
image en probeert te herstellen. De huidige blocker zit na image restore:
Qualcomm/X13s device state, input/VT switching, Wi-Fi en userspace komen niet
betrouwbaar terug.

Niet meer doen zonder expliciete bevestiging: `systemctl hibernate`. Dat kost
steeds een handmatige power-button recovery. Voorlopig alleen directe hooks,
`test_resume`, of eventueel `disk=reboot`.

SSH nuance: key-auth werkt vanaf `deadbeef@l-esp` naar `l-portal`, bijvoorbeeld
`ssh 192.168.1.88`. Deze Codex-sessie draait als `root` en heeft die user key
niet, dus remote commands vanuit hier gebruiken nu nog `sshpass`.

## Configwijzigingen tot nu toe

Repo: `/home/deadbeef/github/nixos`

Gewijzigde relevante files:

- `nixos/laptop/l-portal/disko.nix`
- `nixos/laptop/l-portal/hardware/hardware-configuration.nix`
- `nixos/laptop/l-portal/hardware/bootloader.nix`
- `nixos/laptop/l-portal/default.nix`
- `nixos/laptop/l-portal/README.md`

Storage/initrd:

- Swap is een echte LUKS partitie, geen swapfile.
- Swap heet `cryptswap`.
- `cryptswap` gebruikt `/run/cryptswap.key` in initrd.
- Initrd service `cryptswap-keyfile` mount `/persist` read-only uit de al
  geopende root LUKS en kopieert:

  ```text
  /persist/etc/diskunlock/cryptswap.key -> /run/cryptswap.key
  ```

- Kernel command line bevat:

  ```text
  resume=/dev/mapper/cryptswap
  ```

Clevis/Tang:

- Default boot unlockt root via initrd Wi-Fi + Clevis/Tang.
- `manual-unlock` specialisation schakelt Clevis/Tang uit voor root.
- Swap loopt niet via Clevis/Tang; swap gebruikt de keyfile uit encrypted root.

Tijdelijke debug mitigaties:

- `system.autoUpgrade.enable = lib.mkForce false;`
- logind:

  ```nix
  HandlePowerKey = "ignore";
  HandlePowerKeyLongPress = "ignore";
  ```

- WWAN-facing MHI modules tijdelijk geblacklist:

  ```text
  mhi_pci_generic
  mhi_wwan_ctrl
  mhi_wwan_mbim
  ```

- Base MHI/Wi-Fi modules blijven beschikbaar:

  ```text
  mhi
  qrtr_mhi
  ath11k_pci
  ath11k
  ```

## Tests en resultaten

### Normale reboot

Resultaat: werkt.

Observaties:

- Geen LUKS wachtwoord nodig.
- Initrd Wi-Fi associeert met `diskunlock`.
- `cryptsetup-clevis-root.service` eindigt succesvol.
- `cryptswap-keyfile.service` staged de swap key.
- `cryptswap` opent.
- `systemd-hibernate-resume` draait.
- Zonder image is dit verwacht:

  ```text
  PM: Image not found (code -22)
  ```

### pm_test lagen

Getest:

```text
freezer
devices
platform
processors
core
```

Resultaat: alle lagen kwamen terug met:

```text
PM: hibernation: hibernation exit
```

Conclusie: de basis freeze/thaw en staged hibernate paden zijn niet het primaire
probleem.

### disk=test_resume

Commandvorm:

```bash
echo test_resume > /sys/power/disk
echo disk > /sys/power/state
```

Resultaat: slaagde meerdere keren. Laatste succesvolle test:

```text
lportal-test-resume-20260622-154911-boot-b19f90da-5498-42f5-8857-01f507a38d9a
END ... disk-test_resume rc=0
```

Schrijft een echte hibernate image en herstelt die direct zonder
poweroff/reboot.

Conclusie: image write/restore kan in een gecontroleerde test werken.

### disk=reboot

Commandvorm:

```bash
echo reboot > /sys/power/disk
echo disk > /sys/power/state
```

Resultaat: Lenovo scherm verschijnt automatisch, geen handmatige power button
nodig. Resume bereikt swap image, maar grafische/network state kwam niet
betrouwbaar terug.

Conclusie: beter testpad dan `systemctl hibernate`, maar nog steeds riskant.

Nieuwe test gestart met handmatige pre-hook voor de sysfs call en post-hook na
terugkeer:

```text
lportal-disk-reboot-20260622-155054-boot-b19f90da-5498-42f5-8857-01f507a38d9a
```

Scriptvorm:

```bash
sudo /etc/systemd/system-sleep/x13s-hibernate-device-workarounds pre hibernate
echo reboot | sudo tee /sys/power/disk
echo disk | sudo tee /sys/power/state
sudo /etc/systemd/system-sleep/x13s-hibernate-device-workarounds post hibernate
```

Resultaat: gefaald. De pre-hook liep nu wel schoon:

```text
x13s-hibernate-device-workarounds: unbinding 4-0010 from i2c_hid_of_elan
x13s-hibernate-device-workarounds: unbinding xhci-hcd.5.auto from xhci-hcd
PM: hibernation: hibernation entry
```

Daarna bleef het scherm zwart. Power LED bleef aan, SSH kwam niet terug, en een
handmatige power-button recovery was nodig. Na recovery was de boot-id nieuw:

```text
3a64e602-e951-42d7-86c2-3ca2eba69585
```

Conclusie: het unbinden van `4-0010` plus de `a400000.usb` xHCI controller is
niet voldoende. Deze test bewijst wel dat de hook nu correct uitvoert voor de
reboot-route.

### systemctl hibernate

Commandvorm:

```bash
systemctl hibernate
```

Resultaat: niet meer gebruiken voor nu.

Waargenomen gedrag:

- Machine gaat uit.
- Bij power-on: Clevis/root unlock werkt.
- Resume vanuit swap wordt gestart.
- Scherm wordt grijs, vermoedelijk lock/session screen.
- `Ctrl+Alt+Fn+F1-F4` werkt niet.
- SSH komt niet terug.
- Handmatige power-button recovery nodig.

Conclusie: post-resume kernel/userspace/device state hangt hard. Dit is niet
alleen i3lock.

## Belangrijke logbevindingen

### Eerdere device restore errors

Eerder gezien na resume:

```text
i2c_hid_of_elan 4-0010: PM: failed to restore async: error -6
xhci-hcd xhci-hcd.*.auto: PM: failed to restore async: error -110
```

Daarom is een temporary systemd-sleep hook toegevoegd voor:

- `i2c_hid_of_elan` device `4-0010`
- Qualcomm USB controller:

  ```text
  /sys/devices/platform/soc@0/a4f8800.usb/a400000.usb/xhci-hcd*.auto
  ```

Let op: `xhci-hcd.N.auto` wisselt per boot. Niet hardcoden op `N`.

### False power key storm

Na resume logt logind veel:

```text
Power key pressed short.
```

Eerder leidde dat tot automatische poweroff. Daarom staat logind power-key
handling tijdelijk op `ignore`.

### Hook fouten die al gevonden zijn

De sleep hook draait met beperkte environment. Dit faalde:

```text
systemd-cat: No such file or directory
basename: command not found
```

Daarom moet de hook:

- loggen via `/dev/kmsg`
- geen externe helper commands gebruiken
- shell parameter expansion gebruiken, bijvoorbeeld `${path##*/}` in plaats van
  `basename`

Status: `default.nix` is gepatcht om `basename` te verwijderen en geswitcht naar
generatie:

```text
/nix/store/fff61mvfd8v9yjz9h7dmsxfg4w71w412-nixos-system-l-portal-26.05.20260611.a037402
```

Directe hook-test daarna: geslaagd. De hook unbindt en bindt `4-0010` en de
dynamische `a400000.usb/xhci-hcd.N.auto` zonder `command not found`.

### Laatste echte hibernate poging

Marker:

```text
lportal-hibernate-20260622-153353-boot-cbda0735-30ac-4327-9ae9-0ef05ed7b468
```

Belangrijke logs:

```text
x13s-hibernate-device-workarounds: unbinding 4-0010 from i2c_hid_of_elan
systemd-sleep: basename: command not found
PM: hibernation: Creating image
hibernate: Restored 0 MTE pages
System returned from sleep operation 'hibernate'
PM: hibernation: hibernation exit
```

Daarna:

```text
ath11k_pci ... wmi command timeout
NetworkManager ... Couldn't initialize supplicant interface: Timeout was reached
qcom-battmgr-* ... driver failed to report ... -110
Power key pressed short.
```

Conclusie: de hook liep nog niet correct, maar de kernel kwam ver genoeg om
userspace deels te hervatten. Daarna hangen Qualcomm services/devices.

## Directe hook test

Deze test mag zonder echte hibernate:

```bash
sudo /etc/systemd/system-sleep/x13s-hibernate-device-workarounds pre hibernate
sudo /etc/systemd/system-sleep/x13s-hibernate-device-workarounds post hibernate
```

Eerder resultaat met de oude hook:

```text
unbinding 4-0010 from i2c_hid_of_elan
unbinding xhci-hcd.4.auto from xhci-hcd
binding xhci-hcd.4.auto to xhci-hcd
binding 4-0010 to i2c_hid_of_elan
```

Dit werkte in een normale boot, maar de echte sleep hook faalde later door
`basename` in een restricted PATH.

## Volgende stappen

1. Test direct:

   ```bash
   sudo /etc/systemd/system-sleep/x13s-hibernate-device-workarounds pre hibernate
   sudo /etc/systemd/system-sleep/x13s-hibernate-device-workarounds post hibernate
   ```

2. Controleer dat journal/kernel log geen `command not found` meer bevat.
3. Niet meteen `systemctl hibernate`.
4. Als er toch kernel-image testen nodig zijn, volg deze volgorde:

   ```bash
   echo test_resume | sudo tee /sys/power/disk
   echo disk | sudo tee /sys/power/state
   ```

   Daarna pas eventueel:

   ```bash
   echo reboot | sudo tee /sys/power/disk
   echo disk | sudo tee /sys/power/state
   ```

5. Als post-resume nog hangt, volgende hypotheses isoleren:

   - ath11k/Wi-Fi runtime state na restore
   - qcom-battmgr / pmic-glink / qcom_scm timeouts
   - xss-lock/i3lock alleen als symptoom, niet als root cause
   - xHCI unbind wel/niet nodig
   - alleen `i2c_hid_of_elan` unbind testen versus alleen USB unbind

## Terugdraaien later

Als hibernate stabiel is:

- `system.autoUpgrade` weer aan.
- logind power-key handling terug naar normaal.
- WWAN blacklist verwijderen of versmallen.
- systemd-sleep workaround verwijderen, versmallen, of upstream documenteren.

## 2026-06-22 15:50 disk=reboot met handmatige hooks

Marker:

```text
lportal-disk-reboot-20260622-155054-boot-b19f90da-5498-42f5-8857-01f507a38d9a
```

Test:

```bash
sudo /etc/systemd/system-sleep/x13s-hibernate-device-workarounds pre hibernate
echo reboot | sudo tee /sys/power/disk
echo disk | sudo tee /sys/power/state
sudo /etc/systemd/system-sleep/x13s-hibernate-device-workarounds post hibernate
```

Resultaat:

- Pre-hook liep correct.
- Laatste regels in de oude boot:

  ```text
  x13s-hibernate-device-workarounds: unbinding 4-0010 from i2c_hid_of_elan
  x13s-hibernate-device-workarounds: unbinding xhci-hcd.5.auto from xhci-hcd
  PM: hibernation: hibernation entry
  ```

- Daarna zwart scherm / geen bruikbare lokale input / geen SSH.
- Na hard powercycle is de machine terug in een nieuwe normale boot:

  ```text
  boot-id: 3a64e602-e951-42d7-86c2-3ca2eba69585
  generation: /nix/store/fff61mvfd8v9yjz9h7dmsxfg4w71w412-nixos-system-l-portal-26.05.20260611.a037402
  ```

Huidige boot:

```text
Starting Resume from hibernation...
systemd-hibernate-resume: Unable to resume from device '/dev/mapper/cryptswap' (253:1) offset 0, continuing boot process.
PM: Image not found (code -22)
```

Interpretatie:

- Er is geen nette panic/oops/hung-task log van de mislukking.
- De vorige boot eindigt abrupt bij `PM: hibernation: hibernation entry`.
- De nieuwe boot opent root en cryptswap wel correct, maar vindt geen geldige
  hibernate image meer.
- Daardoor is de concrete crashreden niet uit journald te halen. Meest
  waarschijnlijk: harde hang tijdens of direct na het schrijven/overgaan naar
  `disk=reboot`, voordat journald nog extra regels kon flushen.
- Dit maakt de directe oorzaak nog steeds hardware/kernel-device-state op X13s
  verdacht, niet swap/LUKS/initrd.

## 2026-06-22 16:02/16:03 vergelijking met l-envil

Doel: dezelfde hibernate-aanpak testen op `l-envil` (`192.168.1.112`), een
normalere Intel x86_64 laptop/desktop-achtige machine, om te scheiden of het
probleem generiek in de NixOS hibernate/storage-config zit of specifiek in
`l-portal` / X13s / aarch64 / Qualcomm device state.

Machine:

```text
host: l-envil
arch: x86_64
kernel: Linux 6.18.35
generation: /nix/store/ps76yqhvh4gl33vvramn251gvd8nl4mg-nixos-system-l-envil-26.05.20260611.a037402
boot-id voor test: da38f8b5-ca7d-494d-a3d3-dc5253159ff7
cmdline: resume=/dev/mapper/cryptswap
swap: /dev/dm-1 cryptswap, 72G
disk modes: [platform] shutdown reboot suspend test_resume
```

### l-envil `disk=test_resume`

Marker:

```text
lenvil-test-resume-20260622-160217-boot-da38f8b5-ca7d-494d-a3d3-dc5253159ff7
```

Resultaat:

```text
END ... rc=0
boot-id bleef da38f8b5-ca7d-494d-a3d3-dc5253159ff7
PM: hibernation: hibernation exit
```

Opmerkingen uit de log:

```text
spd5118 14-0050: PM: failed to restore async: error -6
usb root hub lost power or was reset
i915 firmware reload / GuC submission enabled
nvme nvme0: D3 entry latency set to 10 seconds
```

Deze warnings zijn niet fatal: de machine kwam netjes terug.

### l-envil `disk=reboot`

Marker:

```text
lenvil-disk-reboot-20260622-160323-boot-da38f8b5-ca7d-494d-a3d3-dc5253159ff7
```

Test:

```bash
echo reboot > /sys/power/disk
sync
echo disk > /sys/power/state
```

Resultaat:

```text
RETURN ... disk-reboot rc=0 boot=da38f8b5-ca7d-494d-a3d3-dc5253159ff7
PM: hibernation: hibernation exit
```

Belangrijk: de boot-id bleef hetzelfde. Dat betekent dat `l-envil` echt uit de
hibernate-image is teruggekomen, niet als normale nieuwe boot.

### l-envil `systemctl hibernate`

Gebruikersobservatie:

- `systemctl hibernate` op `l-envil` werkte niet.
- De machine bevroor.
- Na ongeveer 10 minuten is de machine met de powerknop uitgezet.

Vorige boot:

```text
boot-id: da38f8b5-ca7d-494d-a3d3-dc5253159ff7
laatste relevante regels:
systemd-logind: The system will hibernate now!
systemd: Starting System Hibernate...
systemd-sleep: Performing sleep operation 'hibernate'...
PM: hibernation: hibernation entry
```

Daarna zijn er geen image-write/restore regels meer in die boot bewaard.

Nieuwe boot na geforceerde poweroff:

```text
boot-id: c958d017-a169-49d8-9729-7c77c78c2b4b
systemd-hibernate-resume-generator: Reported hibernation image: ID=nixos VERSION_ID=26.05 kernel=6.18.35 UUID=4b3c3c4e-5716-48e2-9359-d67d9da4361e offset=0
systemd-hibernate-resume: Unable to resume from device '/dev/mapper/cryptswap' (254:1) offset 0, continuing boot process.
PM: Image not found (code -22)
```

Interpretatie:

- `l-envil` is x86_64 en dus een normalere vergelijking dan `l-portal`, maar
  volledige `systemctl hibernate` faalt daar ook.
- Het verschil met `disk=reboot` is belangrijk: `disk=reboot` restorede in
  dezelfde boot-id en werkte, terwijl `systemctl hibernate` via de normale
  systemd/platform hibernate route bevroor.
- Daardoor is de scope breder dan alleen X13s/aarch64: de generic
  poweroff/platform hibernate route kan ook op x86_64 stuklopen.
- Storage/resume config is nog steeds waarschijnlijk goed genoeg om images te
  schrijven en te vinden, maar de normale hibernate poweroff/resume pad is
  verdacht.

### l-envil verbose hibernate logging

Na de `HibernateMode=shutdown` test bleef `l-envil` vóór poweroff hangen op de
oude i3 sessie. Er was geen zichtbare disk activity. Om te zien waar de kernel
blijft hangen, zijn dezelfde tijdelijke debug kernel parameters als op
`l-portal` toegevoegd:

```text
no_console_suspend
ignore_loglevel
printk.time=1
log_buf_len=16M
initcall_debug
pm_debug_messages
drm.debug=0x1e
```

Deze zijn zichtbaar via NixOS warnings. Reboot vereist voordat ze actief zijn.

Switch/reboot:

```text
generation: /nix/store/nabii75xm6pvv1nzrqc78sq36ryj9z8k-nixos-system-l-envil-26.05.20260611.a037402
boot-id: 521f45bc-6674-4751-9904-5000d087dba5
cmdline: no_console_suspend ignore_loglevel printk.time=1 log_buf_len=16M initcall_debug pm_debug_messages drm.debug=0x1e
sleep.conf: HibernateMode=shutdown
```

Test:

```bash
systemctl hibernate
```

Met guard:

```bash
test "$(hostname)" = l-envil
```

Marker:

```text
lenvil-systemctl-hibernate-shutdown-verbose-20260622-163843
```

Gebruikersobservatie:

- Rond 16:38/16:39 gestart.
- Eerst xss-lock/grijs scherm.
- Om 16:41:15 nog geen Dell-logo gezien.
- Om 16:41:43 nog steeds grijs scherm.
- Machine lijkt nog aan te staan; dus niet door naar poweroff/shutdown.

Interpretatie:

- Dit is geen succesvolle `HibernateMode=shutdown` entry.
- De machine hangt vóór de zichtbare firmware/poweroff fase.
- Omdat er geen Dell-logo/power cycle is geweest, is dit waarschijnlijk een
  hang vóór of tijdens kernel hibernate entry/image write, niet tijdens cold
  restore.
- Met `no_console_suspend` hadden kernelregels zichtbaar moeten zijn als hij ver
  genoeg kwam om console-output te tonen. Dat er alleen grijs lockscreen blijft
  suggereert dat de hang mogelijk vóór de zichtbare kernel-console fase zit, of
  dat de display niet overschakelt naar console.

Nog te doen na hard poweroff/reboot:

- `journalctl -b -1` uitlezen rond marker.
- Checken of de log voorbij `systemd-sleep: Performing sleep operation
  'hibernate'` en `PM: hibernation: hibernation entry` komt.
- Als er geen extra kernelregels zijn: testen met een minimalere route dan
  `systemctl hibernate`, bijvoorbeeld direct `echo shutdown > /sys/power/disk;
  echo disk > /sys/power/state` vanuit een root shell/service, zodat xss-lock,
  logind sleep hooks en user freeze minder ruis geven.

Fix gekozen:

```ini
[Sleep]
HibernateMode=reboot
```

Dit wordt als systemd sleep drop-in geplaatst:

```text
/etc/systemd/sleep.conf.d/10-hibernate-reboot-mode.conf
```

Rationale:

- `disk=reboot` werkte op `l-envil` en behield dezelfde boot-id.
- De default systemd/platform hibernate-route bevroor.
- Door `HibernateMode=reboot` te zetten gebruikt `systemctl hibernate` dezelfde
  bewezen kernelmodus als de handmatige `disk=reboot` test.
- De wijziging is zichtbaar via NixOS `warnings`.

Dezelfde drop-in is ook op `l-portal` toegevoegd, maar daar blijft extra
hardware-specifieke debugging nodig omdat ook `disk=reboot`/resume nog niet
stabiel is.

### Conclusie vergelijking

- `l-envil` werkt met dezelfde basisroute:
  `resume=/dev/mapper/cryptswap`, encrypted swap, `test_resume`, en
  `disk=reboot`.
- Daarmee is de algemene NixOS/storage-aanpak waarschijnlijk goed voor image
  write/restore en `disk=reboot`.
- `l-portal` faalt niet omdat hibernate met encrypted swap principieel fout is.
- Het verschil wijst naar `l-portal`-specifieke hardware/kernel/device-state:
  ThinkPad X13s, aarch64, Qualcomm SC8280XP, ath11k/MHI, qcom-battmgr,
  pmic-glink, I2C HID, xHCI/display resume.
- Kanttekening: `l-envil` heeft ook niet-fatale device warnings, maar userspace
  en kernel komen wél consistent terug. Op `l-portal` stopt logging of userspace
  hard rond echte resume/reboot-hibernate.
- Nieuwe kanttekening: `systemctl hibernate` op `l-envil` faalt volgens de
  gebruiker ook; de machine bevriest en moest na ongeveer 10 minuten met de
  powerknop worden uitgezet. Dus `l-envil` bewijst niet dat de volledige
  systemd/platform hibernate-route goed is. Het bewijst alleen dat
  `test_resume` en `disk=reboot` werken.

## 2026-06-22 volgende l-portal hack

Doel: opnieuw testen op `l-portal`, maar nu de Qualcomm Wi-Fi/MHI device state
uit de oude hibernate image halen en tegelijk kernel logging harder zetten.

Niet aangepast:

- `flake.nix` blijft ongemoeid.
- Geen nieuwe flake inputs.

Config hacks:

- In `nixos/laptop/l-portal/hardware/bootloader.nix` tijdelijke kernel params:

  ```text
  no_console_suspend
  ignore_loglevel
  printk.time=1
  log_buf_len=16M
  initcall_debug
  pm_debug_messages
  drm.debug=0x1e
  ```

- In `nixos/laptop/l-portal/default.nix` extra NixOS warnings toegevoegd,
  zodat dit zichtbaar blijft bij switch/rebuild.
- De bestaande `x13s-hibernate-device-workarounds` hook unbindt nu ook:

  ```text
  pci 0006:01:00.0 from ath11k_pci
  ```

  vóór hibernate en bindt hem terug na resume.

Rationale:

- Initrd mag `ath11k_pci` nog steeds laden om via Wi-Fi/Clevis root te unlocken.
- De oude hibernate image hoeft ath11k niet actief te hebben.
- Eerdere logs wezen naar `ath11k_pci`/MHI/Qualcomm timeouts na restore.
- Als deze hack helpt, zit de bug waarschijnlijk in ath11k/MHI restore state.
- Als deze hack niet helpt, leveren de extra kernel params hopelijk meer logging
  rond het punt waar `l-portal` nu stilvalt.

### Switch/reboot resultaat

Nieuwe generation:

```text
/nix/store/k57cjc4x4dc8h1mgpn8gjdqkr88p3mkb-nixos-system-l-portal-26.05.20260611.a037402
```

Nieuwe boot-id:

```text
a5620f8e-ba79-4b69-9814-04d4cdc22853
```

Kernel cmdline bevat nu:

```text
no_console_suspend ignore_loglevel printk.time=1 log_buf_len=16M initcall_debug pm_debug_messages drm.debug=0x1e
```

Directe hook smoke-test:

```text
x13s-hibernate-device-workarounds: unbinding 0006:01:00.0 from ath11k_pci
x13s-hibernate-device-workarounds: unbinding 4-0010 from i2c_hid_of_elan
x13s-hibernate-device-workarounds: unbinding xhci-hcd.8.auto from xhci-hcd
x13s-hibernate-device-workarounds: binding xhci-hcd.8.auto to xhci-hcd
x13s-hibernate-device-workarounds: binding 4-0010 to i2c_hid_of_elan
x13s-hibernate-device-workarounds: binding 0006:01:00.0 to ath11k_pci
```

De hook kwam terug met `SUCCESS`; SSH bleef bruikbaar.

### l-portal `disk=test_resume` met ath11k unbind

Marker:

```text
lportal-test-resume-ath11k-unbind-20260622-161013-boot-a5620f8e-ba79-4b69-9814-04d4cdc22853
```

Resultaat:

```text
END ... rc=0
boot-id bleef a5620f8e-ba79-4b69-9814-04d4cdc22853
disk=shutdown reboot suspend [test_resume]
```

Gebruikersobservatie: scherm kwam functioneel terug; dit is duidelijk beter dan
de eerdere vastlopers. Dit bewijst nog niet dat echte cold/reboot hibernate
werkt, maar de hook is niet direct destructief en `test_resume` blijft gezond.

### l-portal `disk=reboot` zonder hook door directe sysfs call

Marker:

```text
lportal-disk-reboot-ath11k-unbind-20260622-161204-boot-a5620f8e-ba79-4b69-9814-04d4cdc22853
```

Test gebruikte direct:

```bash
echo reboot > /sys/power/disk
sync
echo disk > /sys/power/state
```

Belangrijke correctie: directe sysfs hibernate voert de systemd sleep hook niet
automatisch uit. Daardoor is de nieuwe ath11k/I2C/xHCI hook in deze poging niet
toegepast. Dat is zichtbaar in de logs: er zijn geen
`x13s-hibernate-device-workarounds` regels rond de hibernate-entry.

Resultaat:

- User zag dat resume echt uit swap startte: swap/image werd tot 100% geladen.
- Daarna zwart scherm.
- Daarna kwam de machine tot een restart/reboot pad.
- SSH kwam terug in een nieuwe boot:

  ```text
  oude boot-id: a5620f8e-ba79-4b69-9814-04d4cdc22853
  nieuwe boot-id: 9bfb9f86-c034-4b81-9cf4-1fb2dfda0b1d
  ```

Relevante log uit de oude boot:

```text
PM: freeze of devices complete
ath11k_pci 0006:01:00.0: PM: ath11k_pci_pm_suspend_late returned 0
xhci-hcd xhci-hcd.8.auto: PM: platform_pm_restore returned 0
i2c_hid_of_elan 4-0010: failed to change power setting.
i2c_hid_of_elan 4-0010: PM: i2c_hid_core_pm_restore [i2c_hid] returns -6
i2c_hid_of_elan 4-0010: PM: failed to restore async: error -6
Call trace:
 pmic_arb_chained_irq+0x130/0x360
 ...
 irq_default_primary_handler threaded ... qpnp_tm_isr [qcom_spmi_temp_alarm]
```

Interpretatie:

- De image wordt nu aantoonbaar gevonden en geladen.
- De machine komt ver genoeg om device restore logs te schrijven.
- Deze test bewijst niet dat de nieuwe unbind hook faalt, want de hook is niet
  uitgevoerd.
- Volgende correcte test: handmatig de hook `pre hibernate` uitvoeren, dan
  `disk=reboot`, en bij terugkeer de hook `post hibernate` laten lopen.

### l-portal `disk=reboot` met handmatige pre-hook

Marker:

```text
lportal-disk-reboot-manual-hook-ath11k-20260622-161625-boot-9bfb9f86-c034-4b81-9cf4-1fb2dfda0b1d
```

Test:

```bash
/etc/systemd/system-sleep/x13s-hibernate-device-workarounds pre hibernate
echo reboot > /sys/power/disk
sync
echo disk > /sys/power/state
/etc/systemd/system-sleep/x13s-hibernate-device-workarounds post hibernate
```

Status tijdens uitvoering:

- Hook is expliciet gestart vóór `echo disk`.
- User ziet opnieuw zwart scherm na de hibernate/resume fase.
- SSH kwam niet binnen normale wachttijd terug.
- User heeft `l-portal` geforceerd uitgezet omdat deze poging te lang duurde
  voor een hibernate test.
- Machine kwam daarna terug met nieuwe boot-id:

  ```text
  oude boot-id: 9bfb9f86-c034-4b81-9cf4-1fb2dfda0b1d
  nieuwe boot-id: 7e7df9ea-d403-4ab1-a8c8-6b6e22f04400
  ```

Pre-hibernate log bevestigt dat de hook deze keer wel draaide:

```text
lportal-hibernate-test: START lportal-disk-reboot-manual-hook-ath11k-20260622-161625-boot-9bfb9f86-c034-4b81-9cf4-1fb2dfda0b1d disk-reboot-manual-hook-ath11k
x13s-hibernate-device-workarounds: unbinding 0006:01:00.0 from ath11k_pci
x13s-hibernate-device-workarounds: unbinding 4-0010 from i2c_hid_of_elan
x13s-hibernate-device-workarounds: unbinding xhci-hcd.8.auto from xhci-hcd
lportal-hibernate-test: PRE_DONE ...
PM: hibernation: hibernation entry
```

Er zijn in deze oude boot geen latere restore-regels bewaard. Dat is anders dan
de vorige directe sysfs test, waar nog `i2c_hid_of_elan ... restore -6` en een
PMIC call trace werden gelogd. Mogelijke verklaringen:

- De machine hing of werd uitgezet voordat journald latere restore-regels kon
  bewaren.
- De handmatige pre-hook veranderde het faalpunt: ath11k/I2C/xHCI waren wel uit
  de image gehaald, maar de machine kwam alsnog niet bruikbaar terug.
- Doordat ath11k vóór hibernate los is, is SSH pas terug als de post-hook of een
  normale nieuwe boot de Wi-Fi weer bindt. Bij een hang vóór post-hook blijft
  netwerk dus weg.

Nog te doen zodra de machine terug online is:

- Niet opnieuw op dezelfde manier testen zonder extra meetpunt.
- Volgende nuttige variant: post-resume niet afhankelijk maken van Wi-Fi/SSH,
  bijvoorbeeld een init/systemd marker op lokale disk of pstore/ramoops, of de
  test doen zonder ath11k unbind maar met alleen I2C/xHCI unbind.

## l-envil status na verbose `systemctl hibernate`

Host:

```text
l-envil / 192.168.1.112 / x86_64
```

Configwijziging die actief was tijdens deze test:

```nix
environment.etc."systemd/sleep.conf.d/10-hibernate-shutdown-mode.conf".text = ''
  [Sleep]
  HibernateMode=shutdown
'';

boot.kernelParams = [
  "no_console_suspend"
  "ignore_loglevel"
  "printk.time=1"
  "log_buf_len=16M"
  "initcall_debug"
  "pm_debug_messages"
  "drm.debug=0x1e"
];
```

Actieve generatie:

```text
/nix/store/nabii75xm6pvv1nzrqc78sq36ryj9z8k-nixos-system-l-envil-26.05.20260611.a037402
```

Boot-id voor de test:

```text
521f45bc-6674-4751-9904-5000d087dba5
```

Boot-id na hard power-cycle:

```text
e98924d4-c1a4-4137-8976-e6a85dcce4b9
```

Testmarker:

```text
lenvil-systemctl-hibernate-shutdown-verbose-20260622-163843
```

Resultaat:

- User zag xss-lock/grijs scherm.
- Er kwam geen Dell-logo en de machine leek niet te poweroffen.
- Na wachten is de machine hard uitgezet en opnieuw gestart.
- De nieuwe boot probeerde wel hibernate-resume metadata te gebruiken, maar er
  was geen geldige image:

  ```text
  systemd-hibernate-resume-generator: Reported hibernation image
  systemd-hibernate-resume: Unable to resume from device '/dev/mapper/cryptswap'
  PM: Image not found (code -22)
  ```

Belangrijke vorige-boot regels:

```text
systemd-logind: The system will hibernate now!
systemd: Starting TLP suspend/resume...
systemd: Finished TLP suspend/resume.
systemd: Starting System Hibernate...
systemd-sleep: Successfully froze unit 'user.slice'.
systemd-sleep: Performing sleep operation 'hibernate'...
kernel: PM: hibernation: hibernation entry
kernel: i915 ... PPS 0 turning VDD off
kernel: i915 ... disabling DC_off
kernel: i915 ... Enabling DC6
kernel: i915 ... Setting DC state from 00 to 02
```

Wat ontbreekt in deze falende `systemctl hibernate` poging:

```text
PM: hibernation: Creating image
PM: hibernation: Preallocating image memory
PM: hibernation: Allocated ...
PM: hibernation: Image created
PM: hibernation: Wrote ...
```

Interpretatie:

- De encrypted swap/resume plumbing is niet het eerste probleem op `l-envil`.
- Directe kernel tests eerder op `l-envil` werkten:
  - `disk=test_resume` kwam terug in dezelfde boot.
  - `disk=reboot` kwam terug in dezelfde boot.
- `systemctl hibernate` hangt vóór image creation, ondanks
  `HibernateMode=shutdown`.
- Het verschil zit waarschijnlijk in de systemd/logind sleep route:
  user.slice freeze, sleep hooks, TLP suspend/resume, xss-lock/logind interactie
  of een userspace/display state rond i915.

Volgende scherpe test:

```bash
test "$(hostname)" = l-envil
echo shutdown > /sys/power/disk
sync
echo disk > /sys/power/state
```

Die test omzeilt systemd/logind/xss-lock en test de kernel shutdown hibernate
route rechtstreeks. Als dit wel uitgaat en daarna resume werkt, zit de bug in
de systemd sleep stack. Als dit ook blijft hangen vóór image creation, zit het
lager in de kernel/device route voor `shutdown`.

### l-envil directe kernel `shutdown` test

Marker:

```text
lenvil-direct-sysfs-shutdown-20260622-164807
```

Test:

```bash
test "$(hostname)" = l-envil
echo shutdown > /sys/power/disk
sync
echo disk > /sys/power/state
```

Resultaat:

- Machine ging weg van SSH na `echo disk`.
- User zette hem daarna met de powerknop aan.
- User zag dat swap/resume geladen werd.
- SSH kwam terug met dezelfde boot-id:

  ```text
  e98924d4-c1a4-4137-8976-e6a85dcce4b9
  ```

- Swap was actief na resume:

  ```text
  /dev/dm-1 partition 72G
  ```

Interpretatie:

- De kernelroute `/sys/power/disk=shutdown` + `/sys/power/state=disk` werkt op
  `l-envil`.
- De encrypted swap/resume config werkt op `l-envil`.
- Het probleem zit dus niet in encrypted swap of resume plumbing, maar in de
  `systemctl hibernate` route rond `systemd-sleep`.
- De directe sysfs-route is een goede diagnose, maar niet de nette permanente
  NixOS/systemd oplossing.

Wiki/manpage check:

- Arch Wiki en kernel docs adviseren voor debugging precies de sysfs knobs:
  `/sys/power/disk` en `/sys/power/state`.
- systemd docs zeggen dat `systemctl hibernate` normaal `systemd-sleep` gebruikt
  en dat de exacte waarden via `sleep.conf` worden ingesteld.
- systemd docs noemen ook dat `systemd-hibernate.service` standaard
  `user.slice` bevriest tijdens sleep. In de falende `systemctl hibernate` log
  was het laatste duidelijke verschil met de werkende directe sysfs route:

  ```text
  systemd-sleep: Successfully froze unit 'user.slice'.
  systemd-sleep: Performing sleep operation 'hibernate'...
  PM: hibernation: hibernation entry
  ```

Volgende officiële fix-poging:

```nix
environment.etc."systemd/sleep.conf.d/10-hibernate-shutdown-mode.conf".text = ''
  [Sleep]
  HibernateMode=shutdown
'';

systemd.services.systemd-hibernate.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS = "false";
```

Dit behoudt `systemctl hibernate`, logind/inhibitors en `systemd-sleep`, maar
schakelt de systemd user-slice freezer uit voor hibernate. Dat sluit aan bij
de bekende systemd v256+ freezer-probleemklasse en bij onze log.

### l-envil officiële freezer-disable variant actief

Nieuwe generatie na switch:

```text
/nix/store/gv4gki52hn3cqz4hiirf85l8jrcniahl-nixos-system-l-envil-26.05.20260611.a037402
```

Na reboot:

```text
boot-id: d10e4dcd-8415-4781-8ebb-cf5009d7ff96
cmdline: no_console_suspend ignore_loglevel printk.time=1 log_buf_len=16M initcall_debug pm_debug_messages drm.debug=0x1e root=fstab resume=/dev/mapper/cryptswap
```

Effectieve service is nog steeds de normale systemd route:

```text
ExecStart=.../systemd-sleep hibernate
SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false
```

`/sys/power/disk` staat na boot op:

```text
platform [shutdown] reboot suspend test_resume
```

Dit is nu de nette testvariant: geen custom `ExecStart`, geen directe
service-override naar een eigen script.

### l-envil succesvolle `systemctl hibernate`

Marker:

```text
lenvil-systemctl-hibernate-freezer-off-20260622-165418
```

Resultaat:

- `systemctl hibernate` startte via de normale systemd unit.
- Machine ging uit/weg van SSH.
- User drukte op de powerknop.
- Resume kwam terug met dezelfde boot-id:

  ```text
  d10e4dcd-8415-4781-8ebb-cf5009d7ff96
  ```

- `systemd-hibernate.service` eindigde met:

  ```text
  Result=success
  ExecStart=.../systemd-sleep hibernate
  SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false
  ```

Belangrijke logregels:

```text
PM: hibernation: Creating image:
PM: hibernation: Need to copy 2543382 pages
PM: hibernation: Hibernation image restored successfully.
Restarting tasks: Done
PM: hibernation: hibernation exit
systemd-sleep: System returned from sleep operation 'hibernate'.
systemd-hibernate.service: Deactivated successfully.
systemd-logind: Operation 'hibernate' finished.
```

Conclusie voor `l-envil`:

- Encrypted swap/resume werkt.
- `HibernateMode=shutdown` werkt.
- De falende factor was zeer waarschijnlijk systemd's default user.slice
  freezer. Met `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` werkt de officiële
  `systemctl hibernate` route.
- Er blijven hardware-waarschuwingen over (`spd5118`, USB context state,
  SOF audio cold boot), maar die blokkeerden deze hibernate/resume niet.

### l-portal `systemctl hibernate` met freezer-disable en X13s hook

Marker:

```text
lportal-systemctl-hibernate-freezer-off-20260622-165908
```

Resultaat:

- Machine ging naar zwart scherm.
- Geen Lenovo-logo gezien.
- Geen SSH/ping.
- User heeft de machine opnieuw aangezet na hard poweroff.
- Nieuwe boot-id:

  ```text
  28853973-b893-45b8-b006-7c9e07cd4105
  ```

Vorige boot bevestigt dat `systemd-sleep` de freezer-disable gebruikte:

```text
systemd-sleep: User sessions remain unfrozen on explicit request ($SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=0).
```

Vorige boot bevestigt ook dat de X13s hook draaide:

```text
x13s-hibernate-device-workarounds: unbinding 4-0010 from i2c_hid_of_elan
x13s-hibernate-device-workarounds: unbinding xhci-hcd.8.auto from xhci-hcd
xhci-hcd xhci-hcd.8.auto: USB bus 6 deregistered
xhci-hcd xhci-hcd.8.auto: USB bus 5 deregistered
PM: hibernation: hibernation entry
systemd-sleep: Performing sleep operation 'hibernate'...
```

Wat ontbreekt:

```text
PM: hibernation: Creating image
PM: hibernation: Need to copy ...
PM: hibernation: Hibernation image restored successfully
```

Interpretatie:

- Deze poging heeft geen hibernate-image geschreven.
- De `l-envil` freezer-fix is actief, maar lost `l-portal` niet op.
- De X13s hook is nu verdacht: eerdere directe sysfs hibernate zonder hook kwam
  ver genoeg om een image te laden/restoren en faalde pas in device restore.
  Pogingen met pre-unbind hooks hangen vóór image creation.
- Volgende stap moet geen volledige hibernate zijn, maar `pm_test` lagen via
  `systemctl hibernate`, met de hook tijdelijk uit of smaller gemaakt.

### l-portal no-op hook en foutieve `pm_test=core` poging

Configwijziging:

- De X13s hook is no-op gemaakt. Hij logt alleen nog dat de ELAN I2C HID/xHCI
  workaround uit staat.
- Actieve generatie:

  ```text
  /nix/store/bv01xkzalhbbl2wiahv1zjwbipg3s1vr-nixos-system-l-portal-26.05.20260611.a037402
  ```

Marker:

```text
lportal-pmtest-core-systemctl-20260622-170553
```

Belangrijke correctie:

- De bedoeling was een droge `pm_test=core`.
- De testscript gebruikte `systemctl hibernate`.
- Op deze host returnt `systemctl hibernate` zodra de job queued is; het wacht
  niet tot `systemd-hibernate.service` klaar is.
- Daardoor liep de shell verder, zette `pm_test` terug naar `none`, en pas
  daarna startte `systemd-sleep`.
- Deze poging was dus alsnog een echte hibernate, geen betrouwbare `pm_test`.

Log:

```text
lportal-hibernate-test: START ... pm_test=core systemctl-hibernate
systemd-logind: The system will hibernate now!
lportal-hibernate-test: END ... rc=0
systemd: Starting System Hibernate...
systemd-sleep: User sessions remain unfrozen on explicit request
x13s-hibernate-device-workarounds: pre hibernate: ELAN I2C HID/xHCI unbind workaround disabled
systemd-sleep: Performing sleep operation 'hibernate'...
PM: hibernation: hibernation entry
```

User-observatie:

- Machine ging uit.
- Bij aanzetten werd root via clevis unlocked.
- Swap werd gedecrypt.
- Resume ging naar 100%.
- Daarna zwart scherm en geen SSH.
- Na hard reset kwam een nieuwe boot terug:

  ```text
  456a3959-6963-4a6f-88ca-9307315f186f
  ```

Narrow log rond 17:06:

- Geen PCI-renumbering zichtbaar in de normale boot erna:
  - NVMe: `0002:01:00.0`
  - WWAN modem: `0004:01:00.0`
  - Wi-Fi: `0006:01:00.0`, driver `ath11k_pci`
- Laatste zichtbare regels vóór de hang zijn vooral `msm_dpu`/DRM atomic
  commits rond eDP.
- Er zijn geen journalregels na `17:06:05`; de post-restore crash/hang schrijft
  dus niets bruikbaars naar journald.

Nieuwe conclusie:

- Zonder unbind-hook haalt `l-portal` weer image write/resume tot 100%.
- De unbind-hook was verantwoordelijk voor de eerdere pre-image hang.
- De resterende fout zit na image restore, waarschijnlijk in Qualcomm
  display/MSM DPU, input/I2C HID, USB/xHCI, PMIC/powerkey of ath11k/MHI resume.
- Een echte `pm_test` moet blokkerend worden aangeroepen, bijvoorbeeld via
  `systemctl start systemd-hibernate.service` terwijl `pm_test` blijft staan,
  of met een directe gecontroleerde `systemd-sleep`/sysfs test.

### l-portal echte `pm_test` reeks met blokkerende service-start

Alle tests draaiden met:

```bash
echo <level> > /sys/power/pm_test
systemctl start systemd-hibernate.service
echo none > /sys/power/pm_test
```

Belangrijk: dit gebruikt `systemd-hibernate.service` rechtstreeks zodat de
aanroep blokkeert tot `systemd-sleep` klaar is. Dit vermijdt de eerdere race
waarbij `systemctl hibernate` alleen de job queue't.

Actieve context:

```text
boot-id: 456a3959-6963-4a6f-88ca-9307315f186f
generation: /nix/store/bv01xkzalhbbl2wiahv1zjwbipg3s1vr-nixos-system-l-portal-26.05.20260611.a037402
SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false
X13s ELAN I2C HID/xHCI hook: no-op
```

Resultaten:

```text
lportal-pmtest-devices-service-20260622-171226     rc=0
lportal-pmtest-platform-service-20260622-171333    rc=0
lportal-pmtest-processors-service-20260622-171423  rc=0
lportal-pmtest-core-service-20260622-171513        rc=0
```

Alle vier kwamen terug met dezelfde boot-id:

```text
456a3959-6963-4a6f-88ca-9307315f186f
```

Representatieve logregels:

```text
systemd: Starting System Hibernate...
systemd-sleep: User sessions remain unfrozen on explicit request ($SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=0).
systemd-sleep: Performing sleep operation 'hibernate'...
PM: hibernation: hibernation entry
PM: hibernation: Basic memory bitmaps created
PM: hibernation: Preallocating image memory
PM: hibernation: Allocated ... pages for snapshot
systemd-sleep: System returned from sleep operation 'hibernate'.
PM: hibernation: hibernation debug: Waiting for 5 second(s).
PM: hibernation: Hibernation image restored successfully.
Restarting tasks: Done
PM: hibernation: hibernation exit
```

Observatie tijdens tests:

- Het scherm werd zwart tijdens de testlagen.
- Het systeem kwam steeds zelfstandig terug.
- SSH kwam terug zonder reboot.

Conclusie:

- `freezer`/`devices`/`platform`/`processors`/`core`-achtige droge
  hibernate-lagen zijn goed genoeg om terug te komen.
- De kernel kan lokaal een snapshot maken en in-place herstellen.
- De echte fout zit dus niet in gewone device freeze/thaw.
- De echte fout zit specifieker in de cold-boot restore uit encrypted swap:
  image wordt gelezen tot 100%, daarna blijft het systeem zwart en komt SSH niet
  terug.
- Dit wijst sterker richting X13s firmware/PSCI/platform resume na poweroff, of
  device state na cold restore, dan naar swap/LUKS/systemd-freezer.

### l-portal: nixos-hardware input gecontroleerd

De flake had drie hardware-inputs:

```text
hardware             github:NixOS/nixos-hardware
nixos-hardware       github:NixOS/nixos-hardware
nixos-hardware-x13s  github:BrainWart/nixos-hardware/x13s-updates
```

`l-portal` importeerde al de officiële module:

```nix
inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x13s
```

De aparte `BrainWart/x13s-updates` input werd dus niet actief gebruikt door
`l-portal`, maar stond wel in de flake en lockfile. Omdat die branch broken of
ongewenst is, is `nixos-hardware-x13s` omgezet naar de officiële upstream:

```nix
nixos-hardware-x13s.url = "github:NixOS/nixos-hardware";
```

Lockfile na update:

```text
nixos-hardware-x13s -> NixOS/nixos-hardware 08018c72174a4df5657f8d94178ac69fb9c243e5
```

Er staat geen `BrainWart` of `x13s-updates` meer in `flake.nix`/`flake.lock`.

Tijdens de vergelijking bleek dat de officiële upstream X13s-module een
hardcoded Wi-Fi MAC (`e4:65:38:52:22:a9`) zou zetten, terwijl de live machine
nu deze Wi-Fi MAC gebruikt:

```text
wlP6p1s0  00:03:7f:12:68:72
```

Om geen MAC-wijziging te introduceren is in `l-portal/default.nix` een lokale
udev-regel toegevoegd die de live MAC behoudt:

```nix
services.udev.extraRules = ''
  ACTION=="add", SUBSYSTEM=="net", KERNELS=="0006:01:00.0", RUN+="${pkgs.iproute2}/bin/ip link set dev $name address 00:03:7f:12:68:72"
'';
```

Switch-resultaat:

```text
/nix/store/nlp5qw6mshmb55rv8fgb9fq9a641z1i8-nixos-system-l-portal-26.05.20260611.a037402
```

Na switch was de live MAC nog correct:

```text
wlP6p1s0 UP 00:03:7f:12:68:72
```

Let op: `/proc/cmdline` toont tot de volgende reboot nog de oude bootgeneratie.
Een reboot is nodig voordat de nieuwe bootloader/initrd-kant van deze config
daadwerkelijk actief is.

### l-portal reboot na officiële nixos-hardware switch

Na de switch naar de officiële hardware-input is `l-portal` gereboot.

Resultaat:

```text
boot-id: a1fded76-d19a-4304-8765-4aa8c71476f5
current-system: /nix/store/nlp5qw6mshmb55rv8fgb9fq9a641z1i8-nixos-system-l-portal-26.05.20260611.a037402
wlP6p1s0: 00:03:7f:12:68:72
```

De kernel commandline gebruikt nu de nieuwe generatie:

```text
init=/nix/store/nlp5qw6mshmb55rv8fgb9fq9a641z1i8-nixos-system-l-portal-26.05.20260611.a037402/init
```

Conclusie: boot, root unlock via clevis, netwerk en MAC-preserving udev-regel
werken na het verwijderen van de BrainWart-input en teruggaan naar officiële
`NixOS/nixos-hardware`.

### l-portal echte hibernate na officiële nixos-hardware switch

Test gestart met marker:

```text
lportal-official-nixos-hardware-systemctl-hibernate-20260622-172823
```

Context:

```text
current-system: /nix/store/nlp5qw6mshmb55rv8fgb9fq9a641z1i8-nixos-system-l-portal-26.05.20260611.a037402
nixos-hardware-x13s: github:NixOS/nixos-hardware 08018c72174a4df5657f8d94178ac69fb9c243e5
```

User-observatie:

- Machine ging naar hibernate.
- Na powerknop ging root unlock via clevis.
- Swap/image restore liep naar 100%.
- Daarna zwart scherm.
- Camera-LED begon te knipperen.
- SSH kwam niet terug binnen de wachtperiode.

Voorlopige conclusie:

- De officiële `nixos-hardware` switch lost de cold-restore hang niet op.
- Omdat de image tot 100% geladen wordt, blijven swap/LUKS/resume plumbing goed.
- Camera-LED activiteit maakt camera/ISP/remoteproc/power-domain state een
  extra verdachte naast display/MSM DPU, I2C HID, PMIC/powerkey en MHI/WWAN.

### l-portal: qcom_camss als verdachte

Na de officiële `nixos-hardware` test kwam de machine niet terug uit echte
hibernate:

```text
marker: lportal-official-nixos-hardware-systemctl-hibernate-20260622-172823
oude boot-id: a1fded76-d19a-4304-8765-4aa8c71476f5
nieuwe boot-id na hard reset: 047fa644-029e-4b01-97c1-4677fd65e46d
```

Vorige boot:

- journald eindigt rond `PM: hibernation: hibernation entry` en daarna
  `Filesystems sync` plus zeer veel `msm_dpu` logging.
- Geen succesvolle `Hibernation image restored successfully` in de echte
  cold-restore route.
- User zag na 100% image restore een zwart scherm en knipperende camera-LED.

Huidige boot laadt onder andere:

```text
qcom_camss
v4l2_async/v4l2_fwnode/videobuf2*/videodev
qcom_q6v5_pas/qcom_sysmon/qcom_glink_smem
msm
ath11k_pci/mhi
```

Gerichte nieuwe workaround:

```nix
boot.blacklistedKernelModules = [
  # bestaande WWAN/MHI blacklist ...
  "qcom_camss"
];
```

Reden: camera is niet essentieel voor suspend-to-disk, en de camera-LED was het
nieuwe zichtbare signaal tijdens de post-restore hang. Als dit geen effect heeft,
moet deze blacklist weer weg of als aparte tijdelijke workaround blijven staan
met duidelijke warning.

### l-portal: alternatief op camera-blacklist, X13s baseline modules in stage-2

De tijdelijke `qcom_camss` blacklist is niet gedeployed. Reden: eerst testen of
het probleem juist komt doordat de X13s baseline hardware-stack wel in initrd
maar niet expliciet in stage-2 geladen wordt.

Nieuwe wijziging:

```nix
boot.kernelModules = [
  "nvme"
  "phy-qcom-qmp-pcie"
  "i2c-core"
  "i2c-hid"
  "i2c-hid-of"
  "i2c-qcom-geni"
  "leds_qcom_lpg"
  "pwm_bl"
  "qrtr"
  "pmic_glink_altmode"
  "gpio_sbu_mux"
  "phy-qcom-qmp-combo"
  "gpucc_sc8280xp"
  "dispcc_sc8280xp"
  "phy_qcom_edp"
  "panel-edp"
  "msm"
];
```

`pcie-qcom` is niet toegevoegd omdat de X13s update-branch die eerder al als
"no longer a module" behandelde.

Evaluatie:

```text
boot.blacklistedKernelModules = firewire_*, mhi_pci_generic, mhi_wwan_ctrl, mhi_wwan_mbim
qcom_camss staat niet in de blacklist
```

### Correctie: stage-2 baseline module test niet gedeployed

Het idee om de X13s baseline modules ook expliciet in `boot.kernelModules` te
zetten is besproken, maar niet gedeployed. Reden: die modules zijn in de normale
boot al aanwezig of initrd-gerelateerd, en dit zou waarschijnlijk vooral ruis
introduceren.

Belangrijker onderscheid:

- Generieke hibernate/resume kernelparameters zoals `resume=`,
  `resume_offset=`, `resumewait`, `resumedelay` en `hibernate=noresume` bepalen
  vooral of/waar/wanneer de image gevonden wordt.
- Op `l-portal` werkt dat al: `/sys/power/resume` is `253:1`,
  `resume_offset` is `0`, en de image wordt tot 100% gelezen.
- De overblijvende fout zit daarom waarschijnlijk niet in de generieke resume
  parameters, maar in driver/platform state na image restore.

Volgende relevantere parameterklasse: driver/module params, vooral `msm.*`
voor eDP/MSM DPU display resume.

### l-portal: gerichte msm/reset_devices test

Nieuwe tijdelijke debug/hack kernelparameters voor de volgende echte hibernate
test:

```text
reset_devices
msm.disable_acd=1
msm.hang_debug=1
msm.dumpstate=1
```

Reden:

- `resume=` en `resume_offset=` werken al: de image wordt gevonden en tot 100%
  gelezen.
- De resterende hang zit direct na image restore.
- Vorige journald-logs eindigen rond MSM/DPU display code en `Filesystems sync`.
- `reset_devices` forceert driver/device reset bij boot/init.
- `msm.disable_acd=1` schakelt GPU ACD uit als mogelijke power-state verdachte.
- `msm.hang_debug=1` en `msm.dumpstate=1` moeten extra MSM diagnostics geven als
  de driver een hang detecteert.

Dit is bewust geen nette eindconfig; er staat een Nix warning bij.

### l-portal reboot met msm/reset_devices params

Na switch/reboot is de nieuwe generatie actief:

```text
current-system: /nix/store/4yd4ck4k9c3y7dmjhq436i7p8j30y7rw-nixos-system-l-portal-26.05.20260611.a037402
boot-id: 2c975f83-ea55-4850-8595-31eaa51142de
```

Live kernel commandline bevat:

```text
reset_devices msm.disable_acd=1 msm.hang_debug=1 msm.dumpstate=1
```

### l-portal: resultaat msm/reset_devices test

Testmarker:

```text
lportal-msm-resetdevices-systemctl-hibernate-20260622-174148
```

Actieve boot voor test:

```text
boot-id voor hibernate: 2c975f83-ea55-4850-8595-31eaa51142de
current-system: /nix/store/4yd4ck4k9c3y7dmjhq436i7p8j30y7rw-nixos-system-l-portal-26.05.20260611.a037402
cmdline bevat: reset_devices msm.disable_acd=1 msm.hang_debug=1 msm.dumpstate=1
/sys/module/msm/parameters: disable_acd=Y, hang_debug=Y, dumpstate=Y
```

User-observatie:

- Hibernate-image restore liep naar 100%.
- Daarna zwart scherm.
- Camera/camera-led bleef knipperen.
- SSH kwam niet terug.
- Na hard reset kwam een nieuwe boot terug:

```text
boot-id na hard reset: b9a8623f-61ac-49e9-b872-2f47fdddfd09
```

Resultaat:

- `reset_devices` + `msm.disable_acd=1` + `msm.hang_debug=1` +
  `msm.dumpstate=1` lost de cold-restore hang niet op.
- Er is geen persistent pstore/ramoops output:

```text
/sys/fs/pstore: empty
```

- `msm.hang_debug`/`msm.dumpstate` leverden geen bruikbare persistente crashdump
  na hard reset.

Conclusie:

- De fout blijft post-image-restore en vóór bruikbare userspace/netwerk.
- De camera-LED observatie blijft opvallend. Omdat MSM-display params geen
  effect hadden, is een volgende gerichte test met camera/media/remoteproc uit
  de resume-image nog steeds logisch, bijvoorbeeld `qcom_camss` tijdelijk niet
  laden of vóór hibernate unbinden, maar alleen als aparte test met duidelijke
  warning.

### l-portal: qcom_camss blacklist test

Na de gefaalde `reset_devices`/`msm.*` test zijn die kernelparameters weer
verwijderd. Nieuwe gerichte test:

```nix
boot.blacklistedKernelModules = [
  "mhi_pci_generic"
  "mhi_wwan_ctrl"
  "mhi_wwan_mbim"
  "qcom_camss"
];
```

Reden:

- De hibernate image wordt gevonden en tot 100% gelezen.
- `reset_devices` en MSM-display debug/workaround parameters veranderden het
  symptoom niet.
- Tijdens de failed restore knippert de camera/camera-led.
- In de normale boot zijn er CAMSS/CCI/power-domain signalen:

```text
i2c-qcom-cci ac4c000.cci: probe ... failed with error -110
qcom-camss ac5a000.camss: Failed to configure power domains: -110
qcom-camss ac5a000.camss: probe ... failed with error -110
wireplumber/libcamera starts Camera camera_manager
```

Doel van deze test: camera/media uit de hibernate image houden en zien of de
cold-restore dan voorbij het zwarte scherm komt.

Correctie op de fysieke observatie:

- Een V4L2 stream-start op `/dev/video0` met `v4l2-ctl` zette het lampje naast
  de camera niet aan.
- Het knipperende lampje tijdens de failed resume is dus waarschijnlijk niet de
  normale camera privacy LED, maar een statuslampje of vergelijkbaar.
- De `qcom_camss` hypothese blijft daarom gebaseerd op de kernel/CAMSS/CCI
  logs, niet op directe bevestiging via dat lampje.

Na reboot met de blacklist:

```text
boot-id: 9d0b4715-0aa1-4ae7-aee0-bbb98d7d3a6d
current-system: /nix/store/75qz4n8cy7svjgy9byxrrcf3h5i40vk6-nixos-system-l-portal-26.05.20260611.a037402
qcom_camss module: niet geladen
/dev/video*: afwezig
/dev/media*: afwezig
```

### l-portal: qcom_camss blacklist resultaat

Testmarker:

```text
lportal-qcom-camss-blacklist-systemctl-hibernate-20260622-175320
```

Actieve context:

```text
boot-id voor hibernate: 9d0b4715-0aa1-4ae7-aee0-bbb98d7d3a6d
current-system: /nix/store/75qz4n8cy7svjgy9byxrrcf3h5i40vk6-nixos-system-l-portal-26.05.20260611.a037402
qcom_camss: niet geladen
/dev/video*: afwezig
/dev/media*: afwezig
```

Resultaat:

- Image restore liep naar 100%.
- Daarna zwart scherm.
- Systeem kwam niet terug naar dezelfde userspace.
- Daarna volgde een automatische reboot/fallback boot.
- Nieuwe boot-id:

```text
304e35e9-5686-4979-9b62-c997aa64e31a
```

Conclusie:

- `qcom_camss` is niet de primaire oorzaak van de cold-restore failure.
- De volgende logische verdachte blijft display/MSM DPU/eDP of de grafische
  userspace rond restore.
- Volgende test: hibernate vanuit `multi-user.target`, zonder actieve GDM/i3/X
  sessie, om userspace/display-stack invloed te isoleren.

### l-portal: multi-user hibernate test resultaat

Testmarker:

```text
lportal-multi-user-hibernate-20260622-175721
```

Voor de hibernate-call is `systemctl isolate multi-user.target` uitgevoerd.
Daarna waren `display-manager.service` en `gdm.service` inactive.

User-observatie:

- Resume image laadde naar 100%.
- Er kwam geen TTY terug.
- Daarna Lenovo scherm en normale boot via clevis unlock.

Resultaat:

```text
boot-id na fallback boot: 0156fb15-eda9-4934-9642-557f6d56a7f3
```

Conclusie:

- Falen gebeurt ook zonder actieve GDM/i3/X/Wayland userspace.
- De oorzaak zit waarschijnlijk lager dan grafische userspace: kernel/display,
  platform firmware/power-domain, remoteproc/audio, input/PMIC, Wi-Fi/MHI, USB,
  of vergelijkbare hardware state.
- Volgende test mag agressiever: vóór hibernate veel services stoppen en
  eventueel modules/drivers unbinden, waarbij visuele terugkeer genoeg is en SSH
  niet noodzakelijk hoeft terug te komen.

### l-portal: aggressive userspace/services-off test attempt 1

Marker bedoeld:

```text
lportal-aggressive-userspace-off-hibernate-20260622-180158
```

Resultaat: geen hibernate uitgevoerd. De transient root unit faalde direct omdat
het script `#!/usr/bin/env bash` gebruikte en de systemd unit environment geen
bruikbare `bash` in `PATH` had:

```text
env: 'bash': No such file or directory
lportal-aggressive-hibernate.service: Failed with result 'exit-code'
```

Correctie voor volgende poging: script met absolute interpreter
`/run/current-system/sw/bin/bash` starten.

### l-portal: aggressive userspace/services-off test attempts 2-3

Attempt 2 gebruikte wel een absolute bash, maar nog geen PATH in de transient
systemd environment. Daardoor faalden basiscommands:

```text
date: command not found
tee: command not found
cat: command not found
```

Attempt 3 zette `PATH=/run/current-system/sw/bin`, maar gebruikte nog
`systemctl isolate multi-user.target`. Dat stopte de transient unit zelf voordat
`echo disk > /sys/power/state` bereikt werd:

```text
lportal-aggressive-hibernate-180338.service: Deactivated successfully
HIBERNATE_TEST ... stage=start
```

Correctie voor volgende poging: geen `isolate` vanuit de transient unit; stop de
services expliciet. Voor permanente NixOS scripts moet dit met store-paden,
bijvoorbeeld `#!${pkgs.bash}/bin/bash` en `lib.makeBinPath`, vergelijkbaar met
het btrfs initrd-script.

### l-portal: aggressive explicit service-stop hibernate test

Testmarker:

```text
lportal-aggressive-explicit-stop-hibernate-20260622-180420
```

Verschil met vorige pogingen:

- Geen `systemctl isolate multi-user.target`, omdat dat de transient unit zelf
  stopte.
- Expliciet gestopt: display-manager/gdm, xlayoutdisplay-hotplug, bluetooth,
  upower, udisks2, fwupd, colord, accounts-daemon, rtkit, systemd-machined.
- `loginctl terminate-user deadbeef` uitgevoerd.
- Wi-Fi/sshd bewust niet gestopt.

Kernel/journal uit de vorige boot:

```text
HIBERNATE_TEST marker=lportal-aggressive-explicit-stop-hibernate-20260622-180420 boot=0156fb15-eda9-4934-9642-557f6d56a7f3 stage=start
HIBERNATE_TEST marker=lportal-aggressive-explicit-stop-hibernate-20260622-180420 stage=before-hibernate explicit-services-stopped
PM: hibernation: hibernation entry
```

User-observatie:

- X crashte/verdween, verwacht door het stoppen van display/user-services.
- Bij handmatig starten werd de image tot 100% gelezen.
- Daarna zwart scherm; geen SSH/TTY/display terug.
- Geforceerde poweroff en normale boot erna.

Nieuwe boot-id na fallback/normal boot:

```text
e418d435-3ace-4e8f-8559-7db22ac4f297
```

Conclusie:

- Het falen blijft aanwezig zonder actieve grafische userspace en zonder de
  meeste desktop services.
- De fout zit vrijwel zeker in kernel/platform hardware restore, niet in i3,
  xss-lock, GDM of user-session state.
- Omdat Wi-Fi/sshd ook niet terugkomen, is het niet alleen een zwart-scherm
  probleem; de restored kernel/userspace komt niet ver genoeg terug voor
  netwerk.
- Volgende zinvolle isolatie: MSM/display-driver uitschakelen of vroeg
  ontbinden, en succes meten via SSH/boot-id. Als hibernate dan wel terugkomt,
  is `msm`/DPU/eDP/display restore de hoofdverdachte.

### l-portal: headless msm blacklist test

Tijdelijke config:

- `msm` uit `boot.initrd.kernelModules` verwijderd.
- `msm` toegevoegd aan `boot.blacklistedKernelModules`.
- `qcom_camss` bleef geblacklist.

Doel: isoleren of Qualcomm display/MSM/DPU/eDP restore de cold-resume hang
veroorzaakt. Verwachte bijwerking: lokaal zwart scherm en geen TTY, omdat de
display-driver bewust uit staat.

Actieve headless generatie:

```text
/run/current-system -> /nix/store/4hcggypw79wjzgadlmmgpx7y5lhpxjcm-nixos-system-l-portal-26.05.20260611.a037402
boot-id voor test: 66e24d57-1820-4e42-acab-20e3b50bf1ce
msm: niet geladen
qcom_camss: niet geladen
sshd/NetworkManager: active
```

Resultaat:

- Hibernate gestart via SSH.
- Machine uitgezet en handmatig aangezet rond 18:16.
- Geen SSH/netwerk terug na restore; rond 18:17:49 nog steeds `No route to host`.
- Na forced poweroff/normal boot kwam hij terug met nieuwe boot-id:

```text
183465a6-2e89-4a96-bade-63a3713fdbca
```

Conclusie:

- `msm` uitschakelen lost de cold-restore failure niet op.
- De failure is niet alleen een lokaal display/TTY probleem; zelfs zonder MSM
  komt netwerk/userspace niet terug.
- De headless wijziging is teruggedraaid in de repo. Volgende test: normale
  display-config, maar netwerk/Wi-Fi/ath11k/MHI vóór hibernate uitzetten om te
  isoleren of de netwerkstack de restore breekt.

### l-portal: intended boot entries

Current decision after the `msm` test:

- default boot entry: debug profile. This keeps the active hibernate debugging
  changes enabled while we are still isolating the X13s failure.
- `normal` specialisation: intended escape hatch with hibernate debug blacklists
  and logind/freezer workarounds disabled.
- `manual-unlock` specialisation: same debug defaults as the main entry, but
  clevis/Tang root unlock disabled so root LUKS can be entered manually if
  network unlock fails.

The previously considered `x13s-headless-msm-off` specialisation was removed,
because `msm`-off did not improve hibernate restore and only made local
console/display unusable.

### l-portal: final boot-entry layout for ongoing debugging

After discussion, the intended boot menu layout is now three useful entries:

1. Default entry: active debug profile until the hibernate issue is found.
   This keeps noisy kernel logging and current hibernate workarounds enabled.
2. `normal` specialisation: normal profile / escape hatch. Intended to disable
   the hibernate debug blacklists and logind/freezer workarounds.
3. `manual-unlock` specialisation: default debug profile, but clevis/Tang root
   unlock disabled so root LUKS can be unlocked manually if network unlock
   fails.

Important correction: a `x13s-headless-msm-off` entry was briefly considered,
but removed because the test already showed that disabling `msm` does not make
resume work and makes local display/TTY unusable.

Current switched generation after adding `normal`:

```text
/nix/store/nriaf2f8f6qkawfcrhc7a09sf3szzni5-nixos-system-l-portal-26.05.20260611.a037402
```

Next planned test: use the default debug entry with normal display/MSM, but stop
network/Wi-Fi/ath11k/MHI before hibernate to test whether the network hardware
state is the failing restore component.

### l-portal: network-off runtime test soft lockup

During the runtime network-off hibernate attempt, local console showed a kernel
soft lockup instead of a clean hibernate transition.

Visible console details from the photo:

```text
rcu: INFO: rcu_sched detected expedited stalls on CPUs/tasks
watchdog: BUG: soft lockup - CPU#0 stuck ... [irq/333-pm-adc]
Call trace:
  regmap_unlock_spinlock
  regmap_bulk_read / regmap_bulk_write
  adc_tm5_gen2_isr [qcom_spmi_adc_tm5]
  irq_thread
```

Interpretation:

- This attempt did not primarily point at Wi-Fi/ath11k as the failure.
- The machine wedged in the Qualcomm SPMI ADC thermal-monitor interrupt path:
  `qcom_spmi_adc_tm5` / `pm-adc`.
- Next debug changes should avoid requiring manual power-button recovery:
  enable panic/reboot on soft lockup and temporarily blacklist
  `qcom_spmi_adc_tm5` in the default debug profile.

### l-portal: debug recovery improvement after pm-adc softlock

Boot after the softlock was confirmed to be the default debug entry:

```text
/run/current-system -> /nix/store/nriaf2f8f6qkawfcrhc7a09sf3szzni5-nixos-system-l-portal-26.05.20260611.a037402
qcom_spmi_adc_tm5: loaded
softlockup_panic: 0
kernel.panic: 0
```

Config change added to the default debug profile:

- Blacklist `qcom_spmi_adc_tm5` after the visible `irq/333-pm-adc` soft lockup.
- Set `kernel.softlockup_panic = 1` and `kernel.panic = 10` so future lockups
  reboot automatically after panic instead of requiring a long power-button
  hold.
- The `normal` specialisation force-clears these debug sysctls and blacklists.

### l-portal: no-network hibernate attempt result

The no-network runtime hibernate attempt was initially considered invalid because
it was interrupted from the operator side, but the previous-boot journal still
contains useful markers.

Marker:

```text
lportal-no-network-reboot-hibernate-20260622-192338
```

Important journal markers:

```text
stage=start boot=cd797e45-19b7-4c53-82b9-1c7f8c3b56df
stage=before-unload modules=qrtr_mhi; ath11k_pci; mhi; ath11k
stage=before-hibernate disk=reboot modules=
PM: hibernation: hibernation entry
```

Interpretation:

- `ath11k_pci`, `ath11k`, `qrtr_mhi`, and `mhi` were successfully unloaded
  before the hibernate entry; the `modules=` field was empty.
- Therefore this test gives useful evidence that Wi-Fi/ath11k/MHI is probably
  not the primary cold-restore cause.
- It is still not a perfect proof, because the test was runtime-driven and the
  operator interrupted/recovered manually, but it is much stronger than the
  earlier failed attempt that soft-locked in `qcom_spmi_adc_tm5`.
- Next suspects should shift back toward broader Qualcomm platform/firmware
  state: PMIC/thermal/regmap, remoteproc/audio DSPs, USB/type-C, power domains,
  clocks, or the X13s-specific kernel patchset.

### l-portal: repeated no-network disk=reboot hibernate test

Marker:

```text
lportal-no-network-reboot-hibernate-20260622-192818
```

Setup:

- Default debug profile.
- `qcom_spmi_adc_tm5` blacklisted and absent from the running module list.
- `kernel.softlockup_panic=1`, `kernel.panic=10` active.
- Runtime script stopped Wi-Fi userspace and unloaded network/MHI modules before
  entering hibernate.
- Hibernate mode was forced through sysfs:

```bash
echo reboot > /sys/power/disk
echo disk > /sys/power/state
```

Confirmed pre-hibernate markers from previous boot:

```text
stage=start boot=366b38aa-214f-4e3a-9c10-50b4bde07290
stage=before-unload modules=qrtr_mhi; ath11k_pci; ath11k; mhi
stage=after-unload rc=0 modules=
stage=before-hibernate disk=reboot
PM: hibernation: hibernation entry
```

User-observed result:

- Image saving reached 100%.
- Machine rebooted by itself through the boot menu path.
- Clevis unlock ran.
- Resume loading ran.
- The old framebuffer/i3 contents appeared again, suggesting the hibernate image
  was restored far enough to put old display memory/state back on screen.
- Mouse, touchscreen, `Ctrl+Alt+F1-F5`, SSH/network did not respond.
- Hard reset was required.
- New boot after recovery:

```text
boot-id: f8e58edc-ef51-4225-ba93-5eba3af148f2
```

Interpretation:

- This is strong evidence against Wi-Fi/ath11k/MHI as the primary failure:
  those modules were successfully unloaded (`rc=0`, `modules=` empty) before the
  hibernate image was created.
- The old framebuffer returning while input/VT/network remain dead suggests the
  restore reaches memory/display state but the restored kernel/platform does not
  continue running normally afterwards.
- The remaining primary suspect class is X13s/SC8280XP cold-restore platform
  state: PMIC/thermal/regmap, PSCI/firmware, remoteproc/audio DSPs, USB/type-C,
  power domains/clocks, or another Qualcomm platform driver that behaves
  differently across real reboot/power-cycle restore than in `pm_test` or
  `test_resume`.

### l-portal: next PMIC/SPMI thermal/ADC isolation

After re-reading the full analysis, the most concrete remaining kernel signal is
not Wi-Fi/MHI or graphical userspace:

- `qcom_spmi_adc_tm5` previously soft-locked in `irq/333-pm-adc`.
- An earlier resume log/call trace also mentioned `qpnp_tm_isr` from
  `qcom_spmi_temp_alarm`.
- In the current debug boot, `qcom_spmi_adc_tm5` is blacklisted and absent, but
  `qcom_spmi_adc5` and `qcom_spmi_temp_alarm` are still loaded.
- The no-network test already unloaded ath11k/MHI before image creation, yet the
  restored system still showed the old framebuffer and then froze.

New targeted debug change in the default `l-portal` boot entry:

```nix
boot.blacklistedKernelModules = [
  "mhi_pci_generic"
  "mhi_wwan_ctrl"
  "mhi_wwan_mbim"
  "qcom_camss"
  "qcom_spmi_adc_tm5"
  "qcom_spmi_temp_alarm"
  "qcom_spmi_adc5"
];
```

Reason:

- This isolates the PMIC/SPMI thermal/ADC path that has produced the only clear
  soft-lockup/call-trace evidence so far.
- It is deliberately scoped to the debug default entry.
- The `normal` specialisation still force-clears debug blacklists, logind hacks,
  hibernate environment overrides, and debug sysctls.

Expected risk:

- Battery/thermal sensor reporting may be degraded in this debug boot.
- This is acceptable as a short hibernate isolation test, but it is not a
  permanent desired configuration unless it proves necessary and safe.

### l-portal: PMIC/SPMI blacklist test result, ath11k crash evidence

New generation for this test:

```text
/nix/store/qy8g5lx3s6f93asczhkzjwf188xld80l-nixos-system-l-portal-26.05.20260611.a037402
```

After reboot the intended PMIC/SPMI modules were absent:

```text
qcom_spmi_adc_tm5: absent
qcom_spmi_temp_alarm: absent
qcom_spmi_adc5: absent
qcom_camss: absent
ath11k_pci/ath11k/mhi/qrtr_mhi: loaded
```

Hibernate test:

```text
marker: lportal-pmic-spmi-blacklist-disk-reboot-20260622-194037
boot before test: 6b883412-d90a-48f7-9878-1cfe2479b995
boot after panic/recovery: 9189d423-29ab-4cb6-9b83-4c86d438b6b6
```

Pre-hibernate journal markers:

```text
HIBERNATE_TEST marker=lportal-pmic-spmi-blacklist-disk-reboot-20260622-194037 stage=start
HIBERNATE_TEST marker=lportal-pmic-spmi-blacklist-disk-reboot-20260622-194037 stage=before-hibernate disk=reboot modules=
PM: hibernation: hibernation entry
```

`modules=` was empty for the PMIC/SPMI grep, so the targeted PMIC/SPMI modules
were not in the hibernate image.

User-visible result:

- Hibernate image restore reached 100%.
- Then black screen.
- Then kernel oops/panic appeared on the local console.

Photo `/home/deadbeef/Downloads/IMG_20260622_194218478.jpg` shows the useful
crash evidence. Important visible lines:

```text
qcom_scm firmware:scm: qseecom: scm call failed with error -22
ath11k_core_restart
ath11k_ce_get_shadow_config
ath11k_core_qmi_firmware_ready
Unable to handle kernel NULL pointer dereference
```

Interpretation:

- The PMIC/SPMI blacklist did not fix hibernate.
- The next concrete failure is now Qualcomm Wi-Fi/ath11k/QMI/SCM during
  post-restore restart/firmware-ready handling.
- The crash is not preserved in `journalctl -b -1`; the previous boot journal
  still ends at `PM: hibernation: hibernation entry`.
- Do not use a global kernel `module_blacklist=ath11k_pci` blindly, because
  the initrd Clevis path uses internal Wi-Fi to unlock root.
- Next configuration direction: keep ath11k available for initrd/Clevis if
  possible, but keep ath11k out of the stage-2 hibernate image or unload it
  before hibernate and only re-enable it after a successful resume.

### l-portal: no-ath11k-image test and debug repro

Test intent:

- Keep ath11k available for initrd/Clevis.
- Stop NetworkManager and unload ath11k/MHI immediately before hibernate so the
  restored image does not contain a running Wi-Fi/MHI stack.
- Use `disk=reboot`.

Observed result from the no-ath11k-image attempt:

- Black screen after restore.
- Console showed `Finished resyncing variable state`.
- System then fell back through the Lenovo boot screen and normal boot.
- This means unloading ath11k/MHI avoids the visible ath11k oops, but does not
  make cold hibernate resume successful.

Interpretation:

- ath11k is a real crash path when it is present in the restored image, but it
  is not proven to be the only underlying blocker.
- The deeper failure still happens after the image has been restored and kernel
  resume has progressed far enough to touch EFI variable state.

Then a deliberate default-debug repro was run with ath11k/MHI active:

```text
marker: lportal-repro-ath11k-debug-disk-reboot-20260622-195140
boot before test: 494816d0-0a6b-4687-a260-2d2b03775569
boot after recovery: 267c2ea8-d4dc-4bf5-9083-231fc298d750
system: /nix/store/qy8g5lx3s6f93asczhkzjwf188xld80l-nixos-system-l-portal-26.05.20260611.a037402
```

Pre-hibernate markers confirm debug profile and ath11k/MHI present:

```text
stage=sysctl softlockup_panic=1 panic=10
stage=modules modules=qrtr_mhi; ath11k_pci; ath11k; mac80211; cfg80211; mhi; qmi_helpers
stage=before-state disk=shutdown [reboot] suspend test_resume
```

User-visible console after restore:

```text
PM: hibernation: Hibernation image restored successfully.
PM: hibernation: Basic memory bitmaps freed
OOM killer enabled.
Restarting tasks: Starting
probe of mhi0_IPCR returned 0 after 1640 usecs
```

Then the machine automatically rebooted/fell back.

Important logging caveat:

- `journalctl -b -1 -k` does not contain the late post-restore lines shown on
  the photo; it ends earlier around MSM/DRM output.
- One journal file was reported truncated.
- Therefore the phone photos are currently more useful than persistent journald
  for the precise post-restore failure point.

Updated current diagnosis:

- Storage, initrd, root Clevis, cryptswap unlock, and image read are working.
- The hibernate image is restored successfully.
- The failure occurs after image restore, while restarting tasks/devices.
- Visible suspects now cluster around Qualcomm platform resume after cold
  restore: MHI/IPCR, ath11k/QMI/SCM, EFI variable resync, and possibly MSM/DPU
  because the persistent journal stops amid DRM output.

### l-portal: can we hook at `mhi0_IPCR`?

Question: can the hibernate failure be hooked around the last visible
`probe of mhi0_IPCR returned 0` line?

Important limitation:

- There is no userspace hook exactly between kernel `Restarting tasks` and the
  `mhi0_IPCR` probe.
- A systemd `post hibernate` hook runs only after the kernel has resumed far
  enough to run userspace again; the failing path does not reliably reach that
  point.
- The only realistic userspace-style workaround is a `pre hibernate` hook that
  unbinds the risky device before the image is created, plus a `post hibernate`
  rebind if resume succeeds.

Runtime smoke test:

```bash
echo mhi0_IPCR > /sys/bus/mhi/drivers/qcom_mhi_qrtr/unbind
echo mhi0_IPCR > /sys/bus/mhi/drivers/qcom_mhi_qrtr/bind
```

Observed journal:

```text
MHI_IPCR_SMOKE start boot=267c2ea8-d4dc-4bf5-9083-231fc298d750
MHI_IPCR_SMOKE unbind mhi0_IPCR
ath11k_pci 0006:01:00.0: failed to send WMI_REQUEST_STATS cmd
ath11k_pci 0006:01:00.0: could not request fw stats (-108)
MHI_IPCR_SMOKE unbound-ok
MHI_IPCR_SMOKE bind mhi0_IPCR
probe of mhi0_IPCR returned 0 after 895 usecs
MHI_IPCR_SMOKE done modules=qrtr_mhi; ath11k_pci; ath11k; mhi; ...
ath11k_pci 0006:01:00.0: invalid pdev_id 1 in mgmt_rx_event
WARNING: CPU: 4 PID: 3365 at net/mac80211/sta_info.c:1543 __sta_info_destroy_part2...
```

Result:

- `mhi0_IPCR` can technically be unbound and rebound.
- But doing so in a running system poisons the ath11k/Wi-Fi firmware state:
  repeated WMI `-108` errors, invalid `pdev_id`, mac80211 warning, and network
  loss.
- Therefore `mhi0_IPCR` unbind/rebind is not a safe simple systemd-sleep
  workaround.

Current implication:

- The failure cluster is still MHI/IPCR/ath11k/QMI/SCM, but fixing it probably
  needs either a full Wi-Fi/MHI device reset sequence, a kernel/firmware change,
  or avoiding internal Wi-Fi across hibernate entirely.
- A targeted `mhi0_IPCR` hook alone is too narrow and destabilizes ath11k.

### l-portal: `mhi0_IPCR` retest with ethernet dock attached

The user attached a dock/ethernet adapter. New reachable address:

```text
192.168.1.146
interface: enu1u4u4u3
```

This is useful because Wi-Fi can fail without losing all observability.

Retest marker:

```text
mhi-ipcr-retest-20260622-200121
boot: caa3ee51-bacd-4eed-b33a-94dca6f303cc
```

Sequence:

```text
MHI_IPCR_RETEST ... stage=unbind
MHI_IPCR_RETEST ... stage=after-unbind driver=.../mhi0_IPCR/driver
MHI_IPCR_RETEST ... stage=bind
probe of mhi0_IPCR returned 0 after 1765 usecs
MHI_IPCR_RETEST ... stage=after-bind driver=/sys/bus/mhi/drivers/qcom_mhi_qrtr
MHI_IPCR_RETEST ... stage=ip addr=wlP6p1s0 UP 192.168.1.88/24 ...
MHI_IPCR_RETEST ... stage=nm state=GENERAL.STATE:100 (connected)
MHI_IPCR_RETEST ... stage=done
```

About 45 seconds later:

```text
ath11k_pci 0006:01:00.0: failed to send WMI_STA_POWERSAVE_PARAM_CMDID
ath11k_pci 0006:01:00.0: failed to setup powersave: -108
ath11k_pci 0006:01:00.0: failed to send WMI_REQUEST_STATS cmd
ath11k_pci 0006:01:00.0: could not request fw stats (-108)
wlP6p1s0: deauthenticating ... by local choice
wlP6p1s0: HW problem - can not stop rx aggregation ...
wlP6p1s0: failed to remove key ... from hardware (-108)
WARNING: CPU: ... at net/mac80211/sta_info.c:1543 __sta_info_destroy_part2...
```

Final state while reachable over ethernet:

```text
enu1u4u4u3 UP 192.168.1.146/24
wlP6p1s0 DOWN / NetworkManager disconnected
mhi0_IPCR bound to qcom_mhi_qrtr
ath11k_pci/ath11k/mhi/qrtr_mhi still loaded
```

Conclusion:

- `mhi0_IPCR` unbind/rebind is technically possible and does not immediately
  panic the whole machine.
- It reliably poisons ath11k firmware/WMI state afterwards.
- The earlier disappearance from `192.168.1.88` was Wi-Fi failure, not whole
  machine death.
- Ethernet/dock gives a much better observability path for further hibernate
  tests that deliberately break internal Wi-Fi.

Switch result for PMIC/SPMI isolation:

```text
new generation: /nix/store/qy8g5lx3s6f93asczhkzjwf188xld80l-nixos-system-l-portal-26.05.20260611.a037402
```

A reboot is required before the new module blacklists can be verified.

### l-portal: stop-state / cleanup

After repeated cold hibernate restore tests, the normal profile was restored to
a non-debug baseline:

- Default boot uses the normal X13s kernel parameters only.
- Debug kernel logging, softlockup panic/reboot, power-key-ignore handling, and
  hibernate isolation module blacklists live only in the `debug` specialisation.
- The `manual-unlock` specialisation remains the Clevis-off boot path.
- `system.autoUpgrade` is enabled again in the normal profile.
- `systemd-hibernate.service` is intentionally blocked in the normal profile.

The one expected NixOS warning is:

```text
l-portal: systemctl hibernate is intentionally blocked because X13s cold hibernate restore currently crashes after image restore; use documented debug sysfs tests only.
```

Runtime verification after the cleanup switch:

```text
systemd-hibernate.service override:
ExecStart=
ExecStart=/nix/store/...-l-portal-block-hibernate

sudo systemctl start systemd-hibernate.service
rc=1
ERROR: hibernate is disabled on l-portal.
Reason: X13s cold hibernate restore currently crashes after the image is restored.
See: nixos/laptop/l-portal/hibernate-analyse.md
```

The running kernel can still show old debug parameters until the next reboot if
the machine was booted through the debug entry. That does not mean the default
boot entry still contains them.
