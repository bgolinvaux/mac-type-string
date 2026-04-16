default:
    @just --list

# Build the release binary
build:
    swift build -c release

# Run integration tests (requires GUI session + Accessibility permissions)
test: build
    #!/usr/bin/env bash
    set -euo pipefail
    plist="$HOME/Library/Containers/com.apple.TextEdit/Data/Library/Preferences/com.apple.TextEdit.plist"
    # Quit TextEdit, then disable auto-capitalization via PlistBuddy
    # (using `defaults` can hang due to cfprefsd locking)
    osascript -e 'tell application "TextEdit" to quit' 2>/dev/null || true
    sleep 0.5
    /usr/libexec/PlistBuddy -c "Set :NSAutomaticCapitalizationEnabled false" "$plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :NSAutomaticCapitalizationEnabled bool false" "$plist"
    # Force plain text mode (RichText=0) so .txt files are saved as plain text
    /usr/libexec/PlistBuddy -c "Set :RichText 0" "$plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :RichText integer 0" "$plist"
    cleanup() {
        osascript -e 'tell application "TextEdit" to quit' 2>/dev/null || true
        sleep 0.5
        /usr/libexec/PlistBuddy -c "Delete :NSAutomaticCapitalizationEnabled" "$plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Delete :RichText" "$plist" 2>/dev/null || true
    }
    trap cleanup EXIT
    swift test

# Install to ~/.local/bin (creates dir if needed, checks PATH)
install: build
    #!/usr/bin/env bash
    set -euo pipefail
    dest="$HOME/.local/bin"
    mkdir -p "$dest"
    cp .build/release/mac-type-string "$dest/mac-type-string"
    echo "✓ Installed to $dest/mac-type-string"
    if echo "$PATH" | tr ':' '\n' | grep -qx "$dest"; then
        echo "✓ $dest is already in your PATH"
    else
        echo ""
        echo "⚠ $dest is not in your PATH."
        echo ""
        echo "Snippet to add to ~/.zshrc:"
        echo ""
        echo '  export PATH="$HOME/.local/bin:$PATH"'
        echo ""
        today=$(date +%Y%m%d)
        read -rp "Want me to add it to ~/.zshrc now? [y/N] " answer
        if [[ "${answer,,}" == "y" ]]; then
            printf '\n# added for mac-type-string on %s\nexport PATH="$HOME/.local/bin:$PATH"\n' "$today" >> ~/.zshrc
            echo "✓ Added to ~/.zshrc — run 'source ~/.zshrc' or open a new terminal."
        else
            echo "Skipped. Add it manually when ready."
        fi
    fi

# Show how to uninstall
uninstall:
    #!/usr/bin/env bash
    set -euo pipefail
    location=$(which mac-type-string 2>/dev/null || true)
    if [[ -n "$location" ]]; then
        echo "mac-type-string is installed at: $location"
        echo "To uninstall, simply delete it:"
        echo ""
        echo "  rm \"$location\""
    else
        echo "mac-type-string is not found in your PATH."
        echo "If you installed it manually, delete it from wherever you put it."
    fi
