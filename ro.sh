#!/bin/bash

echo "=== TE is loading be patient u panzy - Building & Running ==="

# Change to the src directory (where main.odin is)
cd "$(dirname "$0")/src"

odin build . -vet -strict-style -extra-linker-flags:"-lX11"

# Build and run from the src directory (like Sublime does)
odin run . -extra-linker-flags:"-lX11"

echo "Done."
