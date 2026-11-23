#!/bin/sh
# Rebuilds the golden data the GPU is tested against:
#   Fixtures/oracle.json   formulas (the original C++ compiled in double precision)
#   Fixtures/renders.json  render stage + Lyapunov (app/Shaders/render_shared.h compiled in double precision)
set -e
cd "$(dirname "$0")"
FIXTURES=../../Tests/ArgenticCoreTests/Fixtures
clang++ -std=gnu++17 -O1 -fcx-limited-range -Wno-unused-value -Wno-parentheses -o /tmp/argentic-oracle oracle.cpp
/tmp/argentic-oracle > $FIXTURES/oracle.json
/tmp/argentic-oracle renders > $FIXTURES/renders.json
echo "wrote Fixtures/oracle.json ($(wc -c < $FIXTURES/oracle.json) bytes) and renders.json ($(wc -c < $FIXTURES/renders.json) bytes)"
