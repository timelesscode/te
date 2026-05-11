#!/bin/bash

echo "=== TE Games - Building & Running ==="

# Build and run directly from src directory
odin run src -extra-linker-flags:"-lX11 -lGL -ldl -lpthread -lm"

odin build src -extra-linker-flags:"-lX11 -lGL -ldl -lpthread -lm"