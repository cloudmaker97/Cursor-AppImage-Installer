#!/bin/bash

# shellcheck disable=SC2034  # Unused variables are used in log functions
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
DESKTOP_FILE_NAME="cursor.desktop"
APPLICATIONS_DIR="$HOME/.local/share/applications"
VERSIONS_DIR="versions"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
        ls -la . | grep -v "^d" | tail -n +2 || echo "  (no files found)"
        exit 1
    fi
    
    if [[ ${#appimages[@]} -gt 1 ]]; then
        log_warn "Multiple AppImage files found. Using: ${appimages[0]}"
        log_warn "Found files: ${appimages[*]}"
    fi
    
    # Return the first AppImage found
    echo "${appimages[0]}"
}

# Main installation process
main() {
    local current_dir="$(pwd)"
    
    # Check for AppImage and get the filename
    local appimage_name
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
    local desktop_source=""
    local possible_desktop_locations=(
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
        local desktop_files=(squashfs-root/*.desktop squashfs-root/**/applications/*.desktop)
        for file in "${desktop_files[@]}"; do
            if [[ -f "$file" ]]; then
                desktop_source="$file"
                log_warn "Using desktop file: $file"
                break
            fi
        done
    fi
    
    # If no desktop file found, create a basic one
    if [[ -z "$desktop_source" ]]; then
        log_warn "No desktop file found - creating a basic one"
        desktop_source="basic_cursor.desktop"
        cat > "$desktop_source" << 'EOF'
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
    
    # Find icon file
    local icon_source=""
    local possible_icons=(
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
            log_info "Found icon: $icon"
            break
        fi
    done
    
    for icon in "${possible_icons[@]}"; do
        if [[ -f "$icon" ]]; then
            icon_source="$icon"
            break
        fi
    done
    
    if [[ -z "$icon_source" ]]; then
        # Look for any icon files
        mapfile -t icon_files < <(find squashfs-root -name "*.png" -o -name "*.svg" -o -name "*.ico" 2>/dev/null | head -5)
        if [[ ${#icon_files[@]} -gt 0 ]]; then
            icon_source="${icon_files[0]}"
            log_warn "Using icon file: $icon_source"
        fi
    fi
    
    # Move AppImage to versions directory
    local version_timestamp=$(date +"%Y%m%d_%H%M%S")
    local appimage_basename=$(basename "$appimage_name" .AppImage)
    local versioned_name="${appimage_basename}_${version_timestamp}.AppImage"
    local versioned_path="$VERSIONS_DIR/$versioned_name"
    
    log_info "Moving AppImage to versions directory..."
    mv "$appimage_name" "$versioned_path"
    
    # Get absolute paths
    local appimage_full_path="$current_dir/$versioned_path"
    local desktop_dest="$APPLICATIONS_DIR/$DESKTOP_FILE_NAME"
    
    # Copy desktop file
    log_info "Installing desktop entry..."
    cp "$desktop_source" "$desktop_dest"
    
    # Copy icon to a permanent location
    local icon_dest=""
    if [[ -n "$icon_source" ]]; then
        local icon_dir="$HOME/.local/share/icons"
        mkdir -p "$icon_dir"
        local icon_filename="cursor.png"
        icon_dest="$icon_dir/$icon_filename"
        cp "$icon_source" "$icon_dest"
        log_info "Icon copied from: $icon_source"
        log_info "Icon installed to: $icon_dest"
        
        # Verify icon was copied successfully
        if [[ -f "$icon_dest" ]]; then
            log_info "Icon installation verified ✓"
        else
            log_warn "Icon copy failed!"
        fi
    else
        log_warn "No icon found in AppImage"
    fi
    
    # Update desktop file with correct paths and add sandbox flag
    sed -i "s|Exec=.*|Exec=\"$appimage_full_path\" --no-sandbox|g" "$desktop_dest"
    
    if [[ -n "$icon_dest" ]]; then
        # Don't add quotes around the icon path - desktop files don't need them
        sed -i "s|Icon=.*|Icon=$icon_dest|g" "$desktop_dest"
        log_info "Desktop file icon set to: $icon_dest"
    else
        # Remove icon line if no icon found
        sed -i "/^Icon=/d" "$desktop_dest"
        log_warn "No icon found - removed Icon line from desktop file"
    fi
    
    # Show the final desktop file content for verification
    echo ""
    log_info "Final desktop file content:"
    echo "─────────────────────────────────────"
    cat "$desktop_dest"
    echo "─────────────────────────────────────"
    
    # Make desktop file executable
    chmod +x "$desktop_dest"
    
    # Create a symlink to the current version for easy access
    local current_symlink="$VERSIONS_DIR/current.AppImage"
    if [[ -L "$current_symlink" ]] || [[ -f "$current_symlink" ]]; then
        rm "$current_symlink"
    fi
    ln -s "$(basename "$versioned_path")" "$current_symlink"
    
    # Clean up extracted files
    log_info "Cleaning up..."
    if [[ -d "squashfs-root" ]]; then
        rm -rf "./squashfs-root"
    fi
    if [[ -f "basic_cursor.desktop" ]]; then
        rm "./basic_cursor.desktop"
    fi
    
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
    local version_count
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
