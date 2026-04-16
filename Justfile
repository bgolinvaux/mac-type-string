default:
    @just --list

# Build the release binary
build:
    swift build -c release

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
