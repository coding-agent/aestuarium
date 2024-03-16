# Aestuarium

Yet another wayland wallpaper manager using openGL.
<br>
Disclaimer: Aestuarium is still in early stages of development.

### Why another tool for background in wayland?

Because all other tools for background didn't have the features I needed and were not in their plans to implement such features.

### Why the name "Aestuarium" 

It is the latin for [Estuary](https://en.wikipedia.org/wiki/Estuary), I will leave the explanation to your imagination.

### Usage

To set any wallpaper you need to first preload it
```shell
aestuarium --preload /absolute/path/to/file.png
```

To set the wallpaper you need to define the monitor (if no monitor is passed than it will fallback to first monitor found)
```shell
aestuarium -m monitor1 --preload /absolute/path/to/file.png
```

You can unload a specific preloaded file or all

```shell
aestuarium --unload all
```

For further help

```shell
aestuarium --help
```

### Configuration

You can configure aestuarium by creating a `config.ini` file in the `$XDG_CONFIG_DIRS/aestuarium/` folder or refer to [known-folders](https://github.com/ziglibs/known-folders) if you are not in linux.

Config template:

```ini
[monitors]
monitor1=/absolute/path/to/file.png
```

### Dependencies

- [zigimg/zigimg](https://github.com/zigimg/zigimg)
- [getty-zig/json](https://github.com/getty-zig/json)
- [ifeund/zig-wayland](https://codeberg.org/ifreund/zig-wayland)
- [ziglibs/known-folders](https://github.com/ziglibs/known-folders)
- [ziglibs/ini](https://github.com/ziglibs/ini)
- [MasterQ32/zig-args](https://github.com/MasterQ32/zig-args)

