#!/bin/bash

# Cursor AppImage Installer with Desktop Integration and Version Management
# shellcheck disable=SC2034  # Color variables used in functions

set -euo pipefail # Exit on error, undefined vars, pipe failures

# Configuration
readonly DESKTOP_FILE_NAME="cursor.desktop"
readonly APPLICATIONS_DIR="$HOME/.local/share/applications"
readonly VERSIONS_DIR="versions"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for AppImage files and exit if none found
check_appimage() {
    # Use nullglob to handle case when no .AppImage files exist
    shopt -s nullglob
    local appimages=(*.AppImage)
    shopt -u nullglob

    if [[ ${#appimages[@]} -eq 0 ]]; then
        echo ""
        log_error "No AppImage files found in current directory"
        log_error "Please place a Cursor AppImage file in this directory and try again"
        echo ""
        echo "Expected file pattern: *.AppImage"
        echo "Current directory: $(pwd)"
        echo ""
        echo "Available files:"
        # Use find instead of ls | grep for better file handling
        if ! find . -maxdepth 1 -type f -not -name ".*" -exec ls -la {} \; 2>/dev/null | head -10; then
            echo "  (no files found)"
        fi
        exit 1
    fi

    if [[ ${#appimages[@]} -gt 1 ]]; then
        log_warn "Multiple AppImage files found. Using: ${appimages[0]}"
        log_warn "Found files: ${appimages[*]}"
    fi

    # Return the first AppImage found
    echo "${appimages[0]}"
}

# Find desktop file in extracted AppImage
find_desktop_file() {
    local desktop_source=""
    local -a possible_desktop_locations=(
        "squashfs-root/cursor.desktop"
        "squashfs-root/usr/share/applications/cursor.desktop"
        "squashfs-root/share/applications/cursor.desktop"
    )

    for location in "${possible_desktop_locations[@]}"; do
        if [[ -f "$location" ]]; then
            desktop_source="$location"
            break
        fi
    done

    if [[ -z "$desktop_source" ]]; then
        # Look for any .desktop file
        local desktop_files
        mapfile -t desktop_files < <(find squashfs-root -name "*.desktop" -type f 2>/dev/null)
        if [[ ${#desktop_files[@]} -gt 0 ]]; then
            desktop_source="${desktop_files[0]}"
            log_warn "Using desktop file: $desktop_source" >&2  # Send log to stderr
        fi
    fi

    echo "$desktop_source"  # Only output the path
}

# Find icon file in extracted AppImage
find_icon_file() {
    local icon_source=""
    local -a possible_icons=(
        "squashfs-root/co.anysphere.cursor.png"
        "squashfs-root/cursor.png"
        "squashfs-root/resources/app/build/icon.png"
        "squashfs-root/usr/share/icons/hicolor/512x512/apps/cursor.png"
        "squashfs-root/usr/share/icons/hicolor/512x512/apps/co.anysphere.cursor.png"
        "squashfs-root/usr/share/pixmaps/cursor.png"
        "squashfs-root/usr/share/pixmaps/co.anysphere.cursor.png"
        "squashfs-root/icon.png"
        "squashfs-root/app.png"
    )

    for icon in "${possible_icons[@]}"; do
        if [[ -f "$icon" ]]; then
            icon_source="$icon"
            log_info "Found icon: $icon" >&2  # Send log to stderr
            break
        fi
    done

    if [[ -z "$icon_source" ]]; then
        # Look for any icon files
        local icon_files
        mapfile -t icon_files < <(find squashfs-root -name "*.png" -o -name "*.svg" -o -name "*.ico" 2>/dev/null | head -5)
        if [[ ${#icon_files[@]} -gt 0 ]]; then
            icon_source="${icon_files[0]}"
            log_warn "Using icon file: $icon_source" >&2  # Send log to stderr
        fi
    fi

    echo "$icon_source"  # Only output the path
}

# Install icon to permanent location
install_icon() {
    local icon_source="$1"
    local icon_dest=""

    if [[ -n "$icon_source" ]]; then
        local icon_dir="$HOME/.local/share/icons"
        mkdir -p "$icon_dir"
        local icon_filename="cursor.png"
        icon_dest="$icon_dir/$icon_filename"
        cp "$icon_source" "$icon_dest"
        log_info "Icon copied from: $icon_source" >&2  # Send log to stderr
        log_info "Icon installed to: $icon_dest" >&2   # Send log to stderr

        # Verify icon was copied successfully
        if [[ -f "$icon_dest" ]]; then
            log_info "Icon installation verified ✓" >&2  # Send log to stderr
        else
            log_warn "Icon copy failed!" >&2  # Send log to stderr
        fi
    else
        log_warn "No icon found in AppImage" >&2  # Send log to stderr
    fi

    echo "$icon_dest"  # Only output the path
}

# Create or update desktop file
create_desktop_file() {
    local desktop_source="$1"
    local appimage_full_path="$2"
    local icon_dest="$3"
    local desktop_dest="$APPLICATIONS_DIR/$DESKTOP_FILE_NAME"

    # If no desktop file found, create a basic one
    if [[ -z "$desktop_source" ]]; then
        log_warn "No desktop file found - creating a basic one"
        desktop_source="basic_cursor.desktop"
        cat >"$desktop_source" <<'EOF'
[Desktop Entry]
Name=Cursor
Comment=AI-first Code Editor
Exec=placeholder
Icon=cursor
Type=Application
Categories=Development;TextEditor;
StartupWMClass=Cursor
EOF
    fi

    # Copy desktop file
    log_info "Installing desktop entry..."
    cp "$desktop_source" "$desktop_dest"

    # Update desktop file with correct paths and add sandbox flag
    sed -i "s|Exec=.*|Exec=\"$appimage_full_path\" --no-sandbox|g" "$desktop_dest"

    # Handle icon - always replace with our installed icon path if we have one
    if [[ -n "$icon_dest" ]]; then
        # Replace any existing Icon line or add one if missing
        if grep -q "^Icon=" "$desktop_dest"; then
            sed -i "s|Icon=.*|Icon=$icon_dest|g" "$desktop_dest"
        else
            # Add Icon line after Name line
            sed -i "/^Name=/a Icon=$icon_dest" "$desktop_dest"
        fi
        log_info "Desktop file icon set to: $icon_dest"
        
        # Also handle the Desktop Action section if it exists
        if grep -q "^\[Desktop Action" "$desktop_dest"; then
            # Replace Icon in action sections too
            sed -i "/^\[Desktop Action/,/^\[/ { /^Icon=/c\\Icon=$icon_dest ; }" "$desktop_dest"
        fi
    else
        # Remove icon line if no icon found
        sed -i "/^Icon=/d" "$desktop_dest"
        log_warn "No icon found - removed Icon line from desktop file"
    fi

    # Make desktop file executable
    chmod +x "$desktop_dest"

    # Show the final desktop file content for verification
    echo ""
    log_info "Final desktop file content:"
    echo "─────────────────────────────────────"
    cat "$desktop_dest"
    echo "─────────────────────────────────────"

    echo "$desktop_dest"
}

# Clean up temporary files
cleanup_files() {
    log_info "Cleaning up..."
    if [[ -d "squashfs-root" ]]; then
        rm -rf ./squashfs-root
    fi
    if [[ -f "basic_cursor.desktop" ]]; then
        rm ./basic_cursor.desktop
    fi
}

# Main installation process
main() {
    local current_dir
    local appimage_name
    local desktop_source
    local icon_source
    local version_timestamp
    local appimage_basename
    local versioned_name
    local versioned_path
    local appimage_full_path
    local icon_dest
    local desktop_dest
    local current_symlink
    local version_count

    current_dir="$(pwd)"

    # Check for AppImage and get the filename
    appimage_name=$(check_appimage)

    log_info "Found AppImage: $appimage_name"

    # Make AppImage executable
    log_info "Making AppImage executable..."
    chmod +x "$appimage_name"

    # Extract to get desktop file and icon
    log_info "Extracting AppImage to get desktop file and icon..."
    if ! ./"$appimage_name" --appimage-extract >/dev/null 2>&1; then
        log_error "Failed to extract AppImage"
        exit 1
    fi

    # Create directories
    mkdir -p "$APPLICATIONS_DIR"
    mkdir -p "$VERSIONS_DIR"

    # Find desktop file
    desktop_source=$(find_desktop_file)

    # Find icon file
    icon_source=$(find_icon_file)

    # Move AppImage to versions directory
    version_timestamp=$(date +"%Y%m%d_%H%M%S")
    appimage_basename=$(basename "$appimage_name" .AppImage)
    versioned_name="${appimage_basename}_${version_timestamp}.AppImage"
    versioned_path="$VERSIONS_DIR/$versioned_name"

    log_info "Moving AppImage to versions directory..."
    mv "$appimage_name" "$versioned_path"

    # Get absolute paths
    appimage_full_path="$current_dir/$versioned_path"

    # Install icon
    icon_dest=$(install_icon "$icon_source")

    # Create desktop file
    desktop_dest=$(create_desktop_file "$desktop_source" "$appimage_full_path" "$icon_dest")

    # Create a symlink to the current version for easy access
    current_symlink="$VERSIONS_DIR/current.AppImage"
    if [[ -L "$current_symlink" ]] || [[ -f "$current_symlink" ]]; then
        rm "$current_symlink"
    fi
    ln -s "$(basename "$versioned_path")" "$current_symlink"

    # Clean up extracted files
    cleanup_files

    # Update desktop database if available
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPLICATIONS_DIR" 2>/dev/null || true
    fi

    # Summary
    echo ""
    log_info "Installation completed successfully!"
    log_info "- AppImage moved to: $versioned_path"
    log_info "- Current version symlink: $current_symlink"
    log_info "- Desktop entry: $desktop_dest"
    if [[ -n "$icon_dest" ]]; then
        log_info "- Icon installed to: $icon_dest"
    fi
    log_info "- You can now launch Cursor from your application menu"
    echo ""
    log_info "Version management:"
    log_info "- All versions are stored in: $VERSIONS_DIR/"
    log_info "- Current version points to: $versioned_name"
    log_info "- To manage versions, check the $VERSIONS_DIR directory"

    # Show existing versions
    version_count=$(find "$VERSIONS_DIR" -name "*.AppImage" -not -name "current.AppImage" 2>/dev/null | wc -l)
    if [[ $version_count -gt 1 ]]; then
        echo ""
        log_info "Existing versions:"
        find "$VERSIONS_DIR" -name "*.AppImage" -not -name "current.AppImage" -exec ls -la {} \; 2>/dev/null | sed 's/^/  /'
    fi

    # FUSE troubleshooting hint
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_warn "FUSE TROUBLESHOOTING HINT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "If Cursor fails to start with FUSE/sandbox errors, try these solutions:"
    echo ""
    echo "1. 🔧 Install FUSE (choose your distribution):"
    echo "   Ubuntu/Debian: sudo apt update && sudo apt install fuse3 libfuse2"
    echo "   Fedora:        sudo dnf install fuse3 fuse"
    echo "   Arch Linux:    sudo pacman -S fuse3 fuse2"
    echo "   openSUSE:      sudo zypper install fuse3 fuse"
    echo ""
    echo "2. 🔑 Fix FUSE permissions:"
    echo "   # Check if fuse group exists:"
    echo "   getent group fuse"
    echo ""
    echo "   # If it exists, add yourself:"
    echo "   sudo usermod -a -G fuse \$USER"
    echo ""
    echo "   # If fuse group doesn't exist:"
    echo "   sudo groupadd fuse"
    echo "   sudo usermod -a -G fuse \$USER"
    echo "   sudo chgrp fuse /dev/fuse"
    echo "   sudo chmod g+rw /dev/fuse"
    echo ""
    echo "   # OR make /dev/fuse accessible to all (quick fix):"
    echo "   sudo chmod 666 /dev/fuse"
    echo ""
    echo "3. 🔄 After FUSE setup:"
    echo "   - Log out and back in (or run: newgrp fuse)"
    echo "   - Or reboot your system"
    echo ""
    echo "4. ✅ Test FUSE:"
    echo "   ls -l /dev/fuse"
    echo "   groups \$USER"
    echo ""
    echo "5. 🚀 Alternative launch methods if FUSE still doesn't work:"
    echo "   $appimage_full_path --no-sandbox"
    echo "   APPIMAGE_EXTRACT_AND_RUN=1 $appimage_full_path"
    echo ""
    echo "The desktop entry already includes --no-sandbox flag for compatibility."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Run main function
main "$@"
