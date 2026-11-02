#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
# Only inert fake processes and physical private temporary fixtures. Never build.
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s Tests/DevelopmentToolsetChecks -p 'test_*.py'
