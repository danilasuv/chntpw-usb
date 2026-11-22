# chntpw USB

Debian 13 (trixie) Live ISO for working with local Windows accounts using `chntpw` and `ntfs-3g`. Lightweight Openbox desktop, amd64, hybrid ISO for USB with BIOS and UEFI bootloaders. Secure Boot support depends on availability of Debian signed boot packages during the build and must be checked on the target machine.

Этот репозиторий содержит исходники и инструкции. Готовый ISO и Rufus в Git не загружаются; для пересборки ISO нужны Debian 13, пакеты из раздела **Build** и доступ к пакетам Debian.

**Образ пересобран 20.11.2026:** в нём исправлена функция закрепления обоев, которая раньше могла сбрасывать параметры рабочего стола и шрифтов Windows. Также добавлена настройка LightDM `logind-check-graphical=false`, проверенная на компьютере пользователя. Старая флэшка сохраняет прежний образ до повторной записи ISO.

## Быстрый запуск

1. В Rufus выберите флэшку **Generic Flash Disk (16 ГБ)** и файл `live-image-amd64.hybrid.iso`. При запросе режима записи выберите **DD**. Содержимое флэшки будет стёрто.
2. Загрузитесь с флэшки. Окно **Windows Rescue** откроется автоматически. Выберите раздел NTFS и нажмите **Найти пользователей**.
3. Для выдачи или снятия прав администратора, разблокировки и очистки пароля выберите запись по имени и RID и нажмите нужную кнопку.
4. Для нового пароля, создания пользователя и обоев нажмите **Подготовить помощник Windows**. Затем загрузите Windows, войдите с правами администратора и откройте папку **Windows Rescue** на общем рабочем столе. Дважды щёлкните `Start-Windows-Rescue.cmd` и выберите действие кнопкой. Обои закрепляются для всех текущих профилей и шаблона новых пользователей.
5. При ошибке откройте вкладку **Дебаг** и сохраните отчёт до выключения Live-системы.

После записи в режиме **DD** в Проводнике Windows появится отдельный раздел **WALLPAPERS** объёмом 500 МБ. В него можно копировать изображения PNG, JPG, JPEG и BMP. В помощнике Windows кнопка **«Закрепить обои всем»** откроет выбор файла с этого раздела; изначально там лежит присланное фото `wallpaper.png`. Если раздел не получил букву диска, откройте его в «Управлении дисками» и назначьте букву.

## Build

Use a Debian 13 amd64 machine or VM with internet access. Install `live-build`, `dosfstools`, `mtools`, and `xorriso` (`sudo apt update && sudo apt install live-build dosfstools mtools xorriso`), then run `sudo sh build.sh` from this directory. The result is `live-image-amd64.hybrid.iso` plus a `.sha256` checksum. The build appends a 500 MiB FAT32 partition labeled `WALLPAPERS`. Building requires root, disk space, and package downloads. Do not build inside this source folder if it is on a filesystem that lacks Linux permissions and symlinks; copy it to an ext4 filesystem first.

## Use

The desktop signs in automatically and opens **Windows Rescue**. In the **Восстановление** tab, choose the Windows NTFS partition, click **Найти пользователей**, select the account by name and RID, then choose **Сделать администратором**, **Снять права администратора**, **Разблокировать**, or **Очистить пароль**. A confirmation shows the exact device and RID. The program copies SAM, SYSTEM, and SECURITY into a timestamped backup folder on the Windows partition before modifying SAM. It verifies administrator membership after group changes when `sampasswd` reports it. Cyrillic account names are read using hivex when possible; if `sampasswd` omits an account, the hive name and RID still appear.

For a new password, a new local user, or wallpaper, click **Подготовить помощник Windows** after selecting the Windows partition. This copies a folder named **Windows Rescue** to `C:\Users\Public\Desktop`. Boot Windows, sign in with an administrator account, and double-click `Start-Windows-Rescue.cmd` in that folder. Approve Windows UAC. Select a local account for password or administrator changes. The wallpaper button lets you select an image from the `WALLPAPERS` USB partition, then applies Microsoft's per-user wallpaper and prevent-change policies to all existing profiles and the default profile for future users. Sign out and back in to see the wallpaper. An administrator can remove the policy later. New passwords are entered in Windows and are not stored in the rescue log or on the USB image. New accounts are standard users by default.

Debian's packaged `chntpw` cannot reliably set a chosen new password and does not create a Windows account. Those operations run through Windows' own local-account APIs in the companion interface after booting Windows with administrator rights. The companion has its own **Дебаг** tab and log under `C:\ProgramData\WindowsRescue\rescue.log`; it never logs entered passwords.

The **Дебаг** tab shows disk discovery, tool output, errors, account listing, and backup paths. The log is stored in RAM at `/run/rescue-gui/session.log` and disappears on shutdown unless you click **Сохранить отчёт…** and select a writable location. Review the exported report before sharing it; it can contain disk labels and account names. It does not intentionally log password hashes or copy the SAM into the report.

The console is still available for recovery if the desktop fails:

Boot the ISO in a VM first. The console uses the US keyboard layout for reliable login. At the console, sign in with username `user` and password `live` (Debian Live defaults), then run `sudo rescue-menu`. The menu lists NTFS partitions; enter the full device path. It mounts read-only to confirm the Windows SAM location, asks before switching to read/write, then stores copies of the hives in `Windows/System32/config/chntpw-backup-...` on that same Windows partition. `chntpw` handles the final write confirmation. Unmount happens when the program exits. If unmount fails, do not turn off the computer until the partition is unmounted.

To grant administrator rights to a chosen local account, run `sudo promote-admin`. It lists users, asks for the chosen hexadecimal RID, and opens that user's `chntpw` menu. Select `3` (Promote user), then `q`, and confirm writing with `y`. The same NTFS checks and SAM backup run first. Verify the account after rebooting Windows.

The backup occupies the Windows partition and is not protection against failure of that disk. Copy important data to another medium first. NTFS-3G should refuse a hibernated or Fast Startup volume; boot Windows and shut it down fully before editing. A BitLocker volume requires the recovery key and is not supported by this minimal image. This tool is for local accounts, not Microsoft account recovery. Changing account credentials offline can affect access to Windows encrypted data, including EFS-protected files.

To use the new graphical version, write this ISO to the USB drive again after identifying the correct device. Ventoy or Rufus in DD mode can be used. Writing an image erases the selected USB drive.

Package configuration follows the [Debian Live Manual](https://live-team.pages.debian.net/live-manual/html/live-manual.en.html). Packages are from Debian's [chntpw](https://packages.debian.org/trixie/chntpw) and [ntfs-3g](https://packages.debian.org/trixie/ntfs-3g) repositories.
