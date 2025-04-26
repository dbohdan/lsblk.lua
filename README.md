# lsblk.lua

**lsblk.lua** implements a FreeBSD command for listing block devices.
The output of lsblk.lua is modeled on [lsblk(8)](https://linux.die.net/man/8/lsblk) from [util-linux](https://en.wikipedia.org/wiki/Util-linux).
lsblk.lua is implemented in [flua](https://kevans.dev/flua/), a version of Lua (currently Lua 5.4) included in the FreeBSD base system.

lsblk.lua has been tested on FreeBSD 13.4-RELEASE and 14.2-RELEASE.
The ZFS functionality works on Linux and NetBSD with OpenZFS, but the focus of this project is FreeBSD.

## Requirements

FreeBSD 13 or 14 with `/usr/libexec/flua` available (the default).

## Installation

```shell
git clone https://github.com/dbohdan/lsblk.lua
cd lsblk.lua

# Install for the current user.
# You may need to add `~/.local/bin/` to `PATH`.
mkdir -p ~/.local/bin/
install lsblk.lua ~/.local/bin/

# Install for all users.
# Replace `sudo` with `doas` or `su -c` as necessary.
sudo install lsblk.lua /usr/local/bin/
```

## Usage

```none
usage: lsblk.lua [-h] [-V] [-b] [-g] [-z]

List information about block devices.

options:
  -h, --help
          Print this help message and exit

  -V, --version
          Print version number and exit

  -b, --bytes
          Print sizes in bytes instead of human-readable format

  -g, --geom
          Only output information about geoms of class "disk" and "part"

  -z, --zfs
          Only output information about ZFS pools and datasets
```

## Sample output

```none
NAME           MAJ:MIN   SIZE TYPE       FSTYPE MOUNTPOINTS
ada0             0:89   31.6G disk            -
├─ada0p1         0:91    512K part freebsd-boot
├─ada0p2         0:92     30G part  freebsd-uft /
└─ada0p3         0:93    1.6G part freebsd-swap
ada1             0:90      4G disk            -
├─ada1s1         0:95      1G part         ntfs
├─ada1s2         0:96      2G part   linux-data
└─ada1s3         0:97      1G part        fat32 /mnt
                                                /mnt
                                                /tmp/mnt
tank             -:-     1.9G disk            -
├─tank           -:-     192K part          zfs /tank
├─tank/foo       -:-      48K part          zfs /tank/foo
└─tank/foo/bar   -:-      24K part          zfs /tank/foo/bar
```

In this example, `ada1s3` is mounted three times.
The output for multiple mountpoints follows Linux lsblk(8), which prints each on a separate line.

## Note on flua

While flua is only intended for the components of the base system, and Kyle Evans's blog post linked above warns it may change at any time, the needs of lsblk.lua are modest enough that it is unlikely to break and should be easy to fix.
lsblk.lua only requires Lua 5.3–5.4 and `lfs.attributes`.
Should flua be removed or replaced, lsblk.lua can depend on Lua from ports or be ported to flua's replacement.

## Motivation and comparison

I got the idea for lsblk.lua from vermaden's [lsblk](https://github.com/vermaden/lsblk) ([sysutils/lsblk](https://www.freshports.org/sysutils/lsblk/)), the first lsblk implementaton for FreeBSD.
I started writing lsblk.lua because I found it difficult to add a feature (a block device tree printed with [box-drawing characters](https://en.wikipedia.org/wiki/Box-drawing_characters)) and realized I could implement lsblk in Lua without requiring anything outside the base system.

- Comparison:
  - lsblk.lua:
    - Sticks closer to the output format of lsblk(8) from util-linux
    - Outputs different columns
    - Lists ZFS datasets
    - Runs faster (9–22 ms vs. 130–145 ms in [hyperfine](https://github.com/sharkdp/hyperfine) on my machine)
  - vermaden's lsblk:
    - Lists nested partitions
    - Implements a disk mode with the option `-d`/`--disk`
    - Takes an argument for what block device to list

## License

BSD-2-Clause (the FreeBSD license).
See [LICENSE](LICENSE).
