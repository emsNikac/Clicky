# Clicky

A native macOS menu bar app that gives your keyboard the sound of mechanical switches.

## Download and install

**[Download Clicky for macOS (.dmg)](https://github.com/emsNikac/Clicky/releases/latest/download/Clicky.dmg)**

Requires **macOS 15.7 or newer**. [View all releases](https://github.com/emsNikac/Clicky/releases).

1. Download and open **Clicky.dmg**.
2. Drag **Clicky.app** into **Applications**, then eject the disk image.
3. Open **Clicky** from Applications and click the **C** icon in the menu bar.
4. Allow **Clicky** under **System Settings → Privacy & Security → Input Monitoring** for sounds in other applications. Quit and reopen Clicky if macOS requests it. Previews work without keyboard permission.

The current release is not notarized by Apple. If macOS blocks the first launch and you trust this download, go to **System Settings → Privacy & Security → Open Anyway**, then confirm **Open**. See [Apple's instructions](https://support.apple.com/en-us/102445).

## Features

- 13 recorded switch profiles, searchable by name and sound character.
- Physical left/right key positioning and row-specific recordings.
- Separate press/release and space/return/delete samples where available.
- Volume, spatial width, bright/deep tone, release level, and subtle pitch variation.
- Defaults: 85% spatial width, 100% deep tone, 100% key release, and natural variation on. Saved user settings take precedence.
- Gradient volume follows macOS volume. Constant volume follows it up to a chosen threshold on a 16-stage scale, then holds that level.
- 32 overlapping audio voices, predecoded samples, and a peak limiter.
- Persistent settings, optional start at login, and **Control–Option–Command–M** to pause.
- No typed text is read or saved. No network access at runtime. Secure Input pauses monitoring.

The keyboard diagram follows ANSI positioning. Additional ISO/JIS and keypad keys are mapped, but the diagram does not change layout. The normal macOS key stream does not provide strike pressure; variation is modeled. Spatial depth is approximated with stereo placement and row gain, rather than a binaural room simulation. Playback follows the system output device, including headphones.

Constant mode uses a **Volume threshold** from **1/16 to 16/16**. At threshold **3/16**, clicks rise with Mac volume through stage 3 (18.75%), then are attenuated to hold that stage's level as Mac volume rises further. Below the threshold there is no compensation or boost. Fractional system-volume changes follow the same ceiling. Switching modes, outputs, or restarting does not capture a new target. The old saved references and manual correction values no longer affect playback.

Volume controls start **Locked**, with a default threshold of **3/16**. Click **Locked** to unlock, change the stage manually, then click **Unlocked** to lock it again. The value and lock state are saved across launches. Both the menu and Settings show the same controls. Gradient retains its separate percentage slider and saved value; that percentage does not multiply the Constant threshold.

The output's 16-stage dB lookup is built by inverting its native dB-to-slider conversion and cached until the output or its control configuration changes. This handles the built-in output's nonlinear mapping without relying on its inconsistent forward conversion or treating slider positions as linear audio gains. The current output volume is checked on volume notifications and before each key sound. Outputs with only slider volume use a ratio fallback; outputs with no readable volume control cannot enforce the threshold. These are software checks against the device's reported gain, not acoustic speaker measurements. Clicky never changes system volume or accesses the microphone. System mute and zero output volume remain silent.

Volume attenuation happens after tone shaping and peak limiting to preserve brightness and attack. Maximum output includes a fixed 9 dB boost before the limiter and output headroom for transient peaks.

## Build from source

Open `Clicky.xcodeproj` in Xcode and run the **Clicky** scheme.

## Recording credits

Original MP3 recordings from [kbsim](https://github.com/tplai/kbsim), copyright Thomas Lai, distributed under its MIT license. The license is included in the application bundle as `KBSIM-LICENSE.txt`. `recordings.json` records upstream paths, the pinned revision, and SHA-256 checksums. The original MP3 data is unchanged; trimming, gain alignment, and subtle pitch variants happen in memory during loading.

The packs cover Durock Alpaca, Gateron Black/Red Ink, NovelKeys Cream, Turquoise Tealios, Holy Panda, Topre, Cherry MX Black/Brown/Blue, Kailh BOX Navy, SKCM Blue Alps, and IBM buckling spring. MX Blue has no dedicated recordings for large keys, so those use their row's sample. Sound descriptions are descriptive, not measurements. Topre is an electrocapacitive mechanism. These presets reproduce the recorded builds, not every possible keyboard using those switches.

To reproduce the bundled assets, run `python3 Tools/fetch_sounds.py` from this project. It downloads the pinned upstream archive into memory and writes only the required recordings, license, and manifest inside the project. Python 3.9+ and macOS curl are required. This is a development tool; the app itself is offline.

## Verification

`Tools/verify.sh` builds the app in a project-local scratch directory and checks audio, key mapping, and the app icon returned by macOS. Its temporary app uses a separate bundle identifier and is unregistered before the scratch directory is removed on exit. It does not launch Clicky, grant permissions, change login items, or write to an installed application.
