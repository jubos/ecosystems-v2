#!/bin/bash

# Exit on error
set -e

# Detect OS and architecture
detect_platform() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)

    case "$os" in
        "windows"* | "mingw"* | "msys"*)
            case "$arch" in
                "x86_64")
                    echo "windows-x86_64"
                    ;;
                *)
                    echo "Unsupported Windows architecture: $arch"
                    exit 1
                    ;;
            esac
            ;;
        "darwin"*)
            case "$arch" in
                "arm64")
                    echo "macos-aarch64"
                    ;;
                *)
                    echo "Unsupported macOS architecture: $arch"
                    exit 1
                    ;;
            esac
            ;;
        "linux"*)
            case "$arch" in
                "x86_64")
                    echo "linux-x86_64"
                    ;;
                *)
                    echo "Unsupported Linux architecture: $arch"
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Unsupported operating system: $os"
            exit 1
            ;;
    esac
}

# Get the platform
PLATFORM=$(detect_platform)
ZIG_VERSION="0.14.0-dev.2802+257054a14"
NEWLINE=$'\n'

if [ $# -eq 0 ]; then
    echo "crypto-ecosystems 2.0"
    echo "Taxonomy of crypto open source repositories${NEWLINE}"
    echo "USAGE:${NEWLINE}    $0 <command> [arguments...]${NEWLINE}"
    echo "SUBCOMMANDS:"
    echo "    build                      build the ce executable"
    echo "    validate                   build and validate the taxonomy using the migrations data"
    echo "    export <output_file>       export the taxonomy to a json file"
    echo "    test                       run unit tests"
    exit 1
fi

# Build function
setup() {
    echo "Setting up build system for $PLATFORM..."
    ZIG_FILE_ROOT="zig-${PLATFORM}-${ZIG_VERSION}"
    ZIG_PACKAGE="toolchains/${ZIG_FILE_ROOT}.tar.xz"
    echo "Zig Package: ${ZIG_PACKAGE}"
    echo "Running macOS ARM64 build..."
    mkdir -p .tcache
    if [ ! -f ".tcache/$ZIG_FILE_ROOT/zig" ]; then
        tar -xf "${ZIG_PACKAGE}" -C .tcache
    fi
    ZIG_EXEC=".tcache/${ZIG_FILE_ROOT}/zig"
}

# Run the build
setup
if [ ! -f "$ZIG_EXEC" ] || [ ! -x "$ZIG_EXEC" ]; then
    echo "Error: Zig executable not found or not executable at $ZIG_EXEC"
    exit 1
fi
echo "Zig Exec: ${ZIG_EXEC}"

# Validate function
validate() {
    echo "Validating taxonomy..."
    $ZIG_EXEC build run -- validate
}

# Export function
export_taxonomy() {
    # Add export logic here using ZIG_EXECUTABLE
    echo "Other args: ${@}"
    $ZIG_EXEC build run -- export "${@}"
}

# Test function
test() {
    $ZIG_EXEC build test --summary all
}


# Main script logic
case "$1" in
    "build")
        $ZIG_EXEC build
        ;;
    "validate")
        validate "$@"
        ;;
    "export")
        shift
        export_taxonomy "$@"
        ;;
    "test")
        test
        ;;
    *)
        echo "Unknown command: $1"
        exit 1
esac
echo "Build completed successfully for $PLATFORM"
