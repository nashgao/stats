# Stats Custom

<a href="https://github.com/nashgao/stats"><p align="center"><img src="https://github.com/nashgao/stats/raw/master/Stats/Supporting%20Files/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="120"></p></a>

macOS system monitor in your menu bar

## About this fork

Stats Custom is an independently maintained, modified version of [Stats](https://github.com/exelban/stats) by Serhiy Mytrovtsiy. It is not affiliated with or endorsed by the original project.

The original project and this fork are distributed under the [MIT License](LICENSE). The original copyright and permission notice are retained.

## Installation
### Stats Custom
Stats Custom does not yet publish a signed DMG. Build it locally with the verified Xcode 26.6 toolchain:

```bash
git clone https://github.com/nashgao/stats.git
cd stats
open Stats.xcodeproj
```

Select the **Stats** scheme in Xcode and run the app. Future packaged builds will be published on this fork's [Releases page](https://github.com/nashgao/stats/releases).

### Upstream binary
If you want the original upstream application instead of Stats Custom, download it from the [upstream Stats releases](https://github.com/exelban/stats/releases/latest). That binary is maintained by the original project and does not contain this fork's changes.

### Homebrew
Homebrew currently installs the upstream Stats application, not Stats Custom:
```bash
brew install stats
```

### Uninstall
Run the uninstall script bundled with the app (requires administrator privileges to remove the SMC helper):
```bash
sh /Applications/Stats.app/Contents/Resources/Scripts/uninstall.sh
```
The script quits Stats and removes:

   - the SMC helper (`/Library/LaunchDaemons/eu.exelban.Stats.SMC.Helper.plist` and `/Library/PrivilegedHelperTools/eu.exelban.Stats.SMC.Helper`)
   - `Stats.app`
   - application data and preferences (`~/Library/Application Support/Stats`, widget containers, and `eu.exelban.Stats` defaults)

If the app has already been moved to the Trash, the script can be run directly from the repository:
```bash
curl -fsSL https://raw.githubusercontent.com/nashgao/stats/master/Kit/scripts/uninstall.sh | sh
```

### Legacy version
Legacy upstream builds for older systems can be found [here](https://mac-stats.com/downloads).

## Requirements
Stats is supported on macOS 12 (Monterey) and newer.
Beta versions of macOS are not supported - only stable releases.

## Features
Stats is an application that allows you to monitor your macOS system.

 - CPU utilization
 - GPU utilization
 - Memory usage
 - Disk utilization
 - Network usage
 - Battery level
 - Fan's control (not maintained)
 - Sensors information (Temperature/Voltage/Power)
 - Bluetooth devices
 - Multiple time zone clock

## FAQs

### How do you change the order of the menu bar icons?
macOS decides the order of the menu bar items not `Stats` - it may change after the first reboot after installing Stats.

To change the order of any menu bar icon - macOS Mojave (version 10.14) and up.

1. Hold down ⌘ (command key).
2. Drag the icon to the desired position on the menu bar.
3. Release ⌘ (command key)

### Stats icons do not appear in the menu bar
macOS 26 introduced a new privacy control under System Settings → Menu Bar. Apps must be explicitly allowed there to display menu bar items. If Stats is running with at least one module active and one widget enabled, but none of its icons show up in the menu bar, this is almost certainly the cause. More details you can find [here](https://github.com/exelban/stats/issues/3120).

**Solution:** open **System Settings → Menu Bar** and toggle **Stats** ON.

### Desktop widgets not showing the data
Due to a problem with high data load in the system process (`chronod`) responsible for communication between the app and widgets, communication is disabled by default on the Stats side. To enable it, the `macOS widgets` option must be enabled in the Stats settings. More details you can find [here](https://github.com/exelban/stats/issues/2733).

**Solution:** open **Stats Settings** and toggle **macOS widgets** ON.

### How to reduce energy impact or CPU usage of Stats?
Stats tries to be efficient as it's possible. But reading some data periodically is not a cheap task. Each module has its own "price". So, if you want to reduce energy impact from the Stats you need to disable some Stats modules. The most inefficient modules are Sensors and Bluetooth. Disabling these modules could reduce CPU usage and power efficiency by up to 50% in some cases.

### Fan control
Fan control is in legacy mode. It does not receive any updates or fixes. It's not dropped from the app just because in the old Macs it works pretty acceptable. I'm open to accepting fixed or improvements (via PR) for this feature in case someone would like to help with that. But have no option and time to provide support for this feature.

### Sensors show incorrect CPU/GPU core count
CPU/GPU sensors are simply thermal zones (sensors) on the CPU/GPU. They have no relation to the number of cores or specific cores.
For example, a CPU is typically divided into two clusters: efficiency and performance. Each cluster contains multiple temperature sensors, and Stats simply displays these sensors. However, "CPU Efficient Core 1" does not represent the temperature of a single efficient core—it only indicates one of the temperature sensors within the efficiency core cluster.
Additionally, with each new SoC, Apple changes the sensor keys. As a result, it takes time to determine which SMC values correspond to the appropriate sensors. If anyone knows how to accurately match the sensors for Apple Silicon, please contact me.

### App crash – what to do?
Check this fork's [open and closed issues](https://github.com/nashgao/stats/issues) first. If the problem is not already tracked, open a [new Stats Custom issue](https://github.com/nashgao/stats/issues/new) with the macOS version, app version, and reproduction steps.

### External API
Stats Custom does not collect any telemetry or analytics. Its current optional external request is:

- https://api.mac-stats.com – Retrieving the public IP address in the Network module

Automatic update checks and installation are disabled in custom builds. The source is configured to use `https://api.github.com/repos/nashgao/stats/releases/latest` if a future signed distribution enables the updater, but the current custom build does not contact that release endpoint. An external request is still required to obtain the public IP address when that Network feature is enabled.

If you have concerns about these requests, you have a few options:

- propose a PR that allows these features to work without an external server
- block either endpoint using a network filtering app. In that case, do not expect the corresponding release check or public-IP feature to work.

### How to contribute to the project?
Open an issue in [nashgao/stats](https://github.com/nashgao/stats/issues) before starting a substantial change so scope and verification can be aligned. Pull requests should preserve the MIT attribution, the custom-update safety boundary, and the single-source Native Telemetry design contract in [DESIGN.md](DESIGN.md).

## Supported languages
- English
- Polski
- Українська
- Русский
- 中文 (简体) (thanks to [chenguokai](https://github.com/chenguokai), [Tai-Zhou](https://github.com/Tai-Zhou), and [Jerry](https://github.com/Jerry23011))
- Türkçe (thanks to [yusufozgul](https://github.com/yusufozgul) and [setanarut](https://github.com/setanarut))
- 한국어 (thanks to [escapeanaemia](https://github.com/escapeanaemia) and [iamhslee](https://github.com/iamhslee))
- German (thanks to [natterstefan](https://github.com/natterstefan) and [aneitel](https://github.com/aneitel))
- 中文 (繁體) (thanks to [iamch15542](https://github.com/iamch15542) and [jrthsr700tmax](https://github.com/jrthsr700tmax))
- Spanish (thanks to [jcconca](https://github.com/jcconca))
- Vietnamese (thanks to [HXD.VN](https://github.com/xuandung38))
- French (thanks to [RomainLt](https://github.com/RomainLt))
- Italian (thanks to [gmcinalli](https://github.com/gmcinalli))
- Portuguese (Brazil) (thanks to [marcelochaves95](https://github.com/marcelochaves95) and [pedroserigatto](https://github.com/pedroserigatto))
- Norwegian Bokmål (thanks to [rubjo](https://github.com/rubjo))
- 日本語 (thanks to [treastrain](https://github.com/treastrain))
- Portuguese (Portugal) (thanks to [AdamModus](https://github.com/AdamModus))
- Czech (thanks to [mpl75](https://github.com/mpl75))
- Magyar (thanks to [moriczr](https://github.com/moriczr))
- Bulgarian (thanks to [zbrox](https://github.com/zbrox))
- Romanian (thanks to [razluta](https://github.com/razluta))
- Dutch (thanks to [ngohungphuc](https://github.com/ngohungphuc))
- Hrvatski (thanks to [milotype](https://github.com/milotype))
- Danish (thanks to [casperes1996](https://github.com/casperes1996) and [aleksanderbl29](https://github.com/aleksanderbl29))
- Catalan (thanks to [davidalonso](https://github.com/davidalonso))
- Indonesian (thanks to [yooody](https://github.com/yooody))
- Hebrew (thanks to [BadSugar](https://github.com/BadSugar))
- Slovenian (thanks to [zigapovhe](https://github.com/zigapovhe))
- Greek (thanks to [sudoxcess](https://github.com/sudoxcess) and [vaionicle](https://github.com/vaionicle))
- Persian (thanks to [ShawnAlisson](https://github.com/ShawnAlisson))
- Slovenský (thanks to [martinbernat](https://github.com/martinbernat))
- Thai (thanks to [apiphoomchu](https://github.com/apiphoomchu))
- Estonian (thanks to [postylem](https://github.com/postylem))
- Hindi (thanks to [patiljignesh](https://github.com/patiljignesh))
- Finnish (thanks to [eightscrow](https://github.com/eightscrow))
- Bengali (thanks to [adnan29979](https://github.com/adnan29979))
- Tamil (thanks to [sabapathy7](https://github.com/sabapathy7))

You can help by adding a new language or improving the existing translation.

## License
[MIT License](LICENSE)
