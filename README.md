# Cursor AppImage Installer

A simple bash script to install Cursor AI Code Editor AppImages on Linux with proper desktop integration and version management.

## Features

- 🔍 **Auto-detection**: Automatically finds and installs the first `.AppImage` file in the directory
- 📁 **Version Management**: Organizes AppImages in a `versions/` directory with timestamps
- 🖼️ **Desktop Integration**: Creates proper desktop entries with icons
- 🔗 **Symlink Management**: Maintains a `current.AppImage` symlink to the latest version
- 🛡️ **Sandbox Compatibility**: Includes `--no-sandbox` flag to prevent FUSE issues
- 📋 **FUSE Troubleshooting**: Comprehensive guide for common AppImage issues

## Quick Start

1. **Download the installer script**

First navigate to the directory where you want to keep your cursor installation tool and the software versions (e.g. ~/Documents/Tools)

   ```bash
   curl -O https://raw.githubusercontent.com/your-repo/cursor-installer/main/install_cursor.sh
   chmod +x install_cursor.sh
   ```

2. **Download Cursor AppImage**
   - Get the latest Cursor AppImage from [cursor.sh](https://cursor.sh)
   - Place it in the same directory as the installer script

3. **Run the installer**
   ```bash
   ./install_cursor.sh
   ```

4. **Launch Cursor**
   - From application menu: Search for "Cursor"
   - From terminal: `cursor` (if `~/.local/bin` is in your PATH)

## Installation Process

The script performs the following steps:

1. **Detection**: Finds the first `.AppImage` file in the current directory
2. **Extraction**: Temporarily extracts the AppImage to get desktop file and icon
3. **Version Management**: Moves the AppImage to `versions/` with timestamp
4. **Desktop Integration**: 
   - Copies desktop file to `~/.local/share/applications/`
   - Installs icon to `~/.local/share/icons/`
   - Updates paths to point to the correct locations
5. **Symlink Creation**: Creates `versions/current.AppImage` pointing to latest version
6. **Cleanup**: Removes temporary extracted files

## Directory Structure

After installation:
```
your-directory/
├── install_cursor.sh
├── versions/
│   ├── Cursor-1.2.1-x86_64_20250722_125430.AppImage
│   └── current.AppImage -> Cursor-1.2.1-x86_64_20250722_125430.AppImage
└── ~/.local/share/
    ├── applications/cursor.desktop
    └── icons/cursor.png
```

## Requirements

- **Linux** (any distribution)
- **Bash** 4.0 or newer
- **Basic utilities**: `sed`, `chmod`, `ln`, `mkdir`, `cp`, `mv`
- **Required**: FUSE for the AppImage

## FUSE Issues & Solutions

If Cursor fails to start with FUSE/sandbox errors, try these solutions:

### 1. Install FUSE

**Ubuntu/Debian:**
```bash
sudo apt update && sudo apt install fuse3 libfuse2
```

**Fedora:**
```bash
sudo dnf install fuse3 fuse
```

**Arch Linux:**
```bash
sudo pacman -S fuse3 fuse2
```

**openSUSE:**
```bash
sudo zypper install fuse3 fuse
```

### 2. Fix FUSE Permissions

Check if fuse group exists:
```bash
getent group fuse
```

If it exists, add yourself:
```bash
sudo usermod -a -G fuse $USER
```

If fuse group doesn't exist:
```bash
sudo groupadd fuse
sudo usermod -a -G fuse $USER
sudo chgrp fuse /dev/fuse
sudo chmod g+rw /dev/fuse
```

**Quick fix (make /dev/fuse accessible to all):**
```bash
sudo chmod 666 /dev/fuse
```

### 3. After FUSE Setup

- Log out and back in (or run: `newgrp fuse`)
- Or reboot your system

### 4. Test FUSE

```bash
ls -l /dev/fuse
groups $USER
```

### 5. Alternative Launch Methods

If FUSE still doesn't work:
```bash
# Method 1: No sandbox
./versions/current.AppImage --no-sandbox

# Method 2: Extract and run
APPIMAGE_EXTRACT_AND_RUN=1 ./versions/current.AppImage
```

## Troubleshooting

### No AppImage Found
```
[ERROR] No AppImage files found in current directory
```
**Solution**: Place a Cursor `.AppImage` file in the same directory as the script.

### Permission Denied
```bash
chmod +x install_cursor.sh
./install_cursor.sh
```

### Desktop Entry Not Appearing
```bash
# Update desktop database
update-desktop-database ~/.local/share/applications/
```

### PATH Issues
If `cursor` command is not found, add to your shell profile:
```bash
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
source ~/.bashrc
```

## Version Management

### Installing New Versions
1. Download new Cursor AppImage
2. Place in installer directory
3. Run `./install_cursor.sh` again
4. Old versions remain in `versions/` directory

### Switching Versions
```bash
# List available versions
ls -la versions/

# Switch to specific version (manual)
cd versions/
rm current.AppImage
ln -s Cursor-1.2.0-x86_64_20250720_100000.AppImage current.AppImage
```

### Cleaning Old Versions
```bash
# Remove old versions (keep current)
cd versions/
ls -t *.AppImage | tail -n +3 | xargs rm
```

## Uninstallation

```bash
# Remove desktop entry
rm ~/.local/share/applications/cursor.desktop

# Remove icon
rm ~/.local/share/icons/cursor.png

# Remove installed files
rm -rf versions/

# Update desktop database
update-desktop-database ~/.local/share/applications/
```

## Script Options

The script accepts the following behaviors:

- **Multiple AppImages**: Uses the first one found, warns about others
- **Missing Desktop File**: Creates a basic desktop entry automatically
- **Missing Icon**: Continues without icon (uses system default)
- **FUSE Issues**: Automatically adds `--no-sandbox` flag for compatibility

## Contributing

Improvements and bug fixes are welcome! Common areas for enhancement:

- Support for other AppImage applications
- GUI version selection
- Automatic updates
- System-wide installation option

## License

This script is provided as-is under the MIT License. Use at your own risk.

## Support

If you encounter issues:

1. Check the FUSE troubleshooting section above
2. Verify file permissions and paths
3. Check system logs: `journalctl --user -f`
4. Test AppImage manually: `./your-cursor.AppImage --help`

---

**Note**: This is an unofficial installer script. For official support, visit [cursor.sh](https://cursor.sh).
