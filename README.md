# Clicky

A native macOS menu bar app that gives your keyboard the sound of mechanical switches.

Open `Clicky.xcodeproj` in Xcode and run the **Clicky** scheme. Requires macOS 15.7 or newer.
Click the keyboard icon in the menu bar. Allow **Clicky** under **System Settings → Privacy & Security → Input Monitoring** for sounds in other applications. Quit and reopen Clicky if macOS requests it. Previews work without keyboard permission.

- 13 recorded switch profiles, searchable by name and sound character.
- Physical left/right key positioning and row-specific recordings.
- Separate press/release and space/return/delete samples where available.
- Volume, spatial width, bright/deep tone, release level, and subtle pitch variation.
- 32 overlapping audio voices, predecoded samples, and a peak limiter.
- Persistent settings, optional start at login, and **Control–Option–Command–M** to pause.
- No typed text is read or saved. No network access at runtime. Secure Input pauses monitoring.

The keyboard diagram follows ANSI positioning. Additional ISO/JIS and keypad keys are mapped, but the diagram does not change layout. The normal macOS key stream does not provide strike pressure; variation is modeled. Spatial depth is approximated with stereo placement and row gain, rather than a binaural room simulation. Playback follows the system output device, including headphones.

## Recording credits

Original MP3 recordings from [kbsim](https://github.com/tplai/kbsim), copyright Thomas Lai, distributed under its MIT license. The license is included in the application bundle as `KBSIM-LICENSE.txt`. `recordings.json` records upstream paths, the pinned revision, and SHA-256 checksums. The original MP3 data is unchanged; trimming, gain alignment, and subtle pitch variants happen in memory during loading.

The packs cover Durock Alpaca, Gateron Black/Red Ink, NovelKeys Cream, Turquoise Tealios, Holy Panda, Topre, Cherry MX Black/Brown/Blue, Kailh BOX Navy, SKCM Blue Alps, and IBM buckling spring. MX Blue has no dedicated recordings for large keys, so those use their row's sample. Sound descriptions are descriptive, not measurements. Topre is an electrocapacitive mechanism. These presets reproduce the recorded builds, not every possible keyboard using those switches.

To reproduce the bundled assets, run `python3 Tools/fetch_sounds.py` from this project. It downloads the pinned upstream archive into memory and writes only the required recordings, license, and manifest inside the project. Python 3.9+ and macOS curl are required. This is a development tool; the app itself is offline.

## Verification

`Tools/verify.sh` builds the app in a project-local scratch directory, runs the audio and key mapping checks, and removes the scratch directory on exit. It does not launch the app, grant permissions, change login items, or write to an installed application.
