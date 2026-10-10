#!/usr/bin/env python3
#
# Configuration script for Zero compositor
# Reads config directory and generates labwc config files
#
# Not meant to be run by hand, which is why it sits in lib/ rather than the
# project root. ./nested.sh and ./standalone.sh call it
#
# Usage, from the project root:
#   python3 lib/configurator.py --dir <profile-directory> --mode <standalone|nested>
#   python3 lib/configurator.py -d <profile-directory> --mode nested
#   python3 lib/configurator.py -d <profile-directory> --mode nested --config <config.yaml> [--force]
#   ZERO_DIR=./my-config python3 lib/configurator.py --mode standalone
#
from configure.cli import main


if __name__ == '__main__':
    main()