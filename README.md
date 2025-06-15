# OS_Shutdown
Shutdown controller for mpv that allows shutdown after a set number of media files.

## Info
This script was created to allow automatic shutdown of the system after a specific number of files played in mpv.  
It supports both playlist-based playback and automatic folder loading (autoload), even when the playlist is not populated (like in [uosc](https://github.com/tomasklaen/uosc)).

The shutdown can be triggered either:
- after a given number of files (`nfiles`)
- at the end of the playlist
- on mpv closing, depending on configuration

## Features
* set the number of files to trigger shutdown (`nfiles`)
* automatic folder scanning for detecting current position (with extensions filter)
* handles idle states like `--keep-open` and `--idle` with optional timer
* support for scripts like `autoload.lua` or `uosc`
* optional shutdown at playlist end
* optional shutdown on mpv exit (closing)
* manual info on remaining items
* configurable extensions and behavior via `.conf` file
* keybinds to interactively set file count and check remaining

## Usage
Place the [`OS_Shutdown.lua`](./OS_Shutdown.lua) file into mpv’s `scripts` folder and the [`OS_Shutdown.conf`](./OS_Shutdown.conf) file into the `script-opts` folder.

## Keybinds
These can be customized via config.

`Ctrl+ì` - Set the number of files to shutdown after (or disable shutdown with any non-numeric entry)  
`Ctrl+^` - Show info on remaining files  
