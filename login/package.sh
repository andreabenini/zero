#!/bin/bash
#
# Build the login manager and roll the tarball to carry to a test machine.
#     ./login/package.sh [zerodir]
#
# Build machine only. It compiles zero-login, generates the unit, and packs the whole project, binary included,
# into ../<name>.tar.gz. The target machine then needs no compiler and no PAM headers: install.sh installs what
# is in the tarball and never builds.
#
# The argument is where the tree will live on the target, baked into the binary and the unit at build time.
# It has to match the --prefix given to install.sh, so it defaults to the same /opt/zero that install.sh does.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(cd "$HERE/.." && pwd)"
NAME="$(basename "$PROJECT")"
OUT="$(dirname "$PROJECT")/$NAME.tar.gz"

# /opt/zero is the default, unless specified as $1
ZERODIR="${1:-/opt/zero}"

line() {
    echo -en "\n\e[32m"
    printf '%*s\r' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
    echo -e "[ $1 ] \e[0m"
}

# Rebuild from scratch rather than trusting whatever is lying around: the install prefix is compiled in, so a stale binary is a wrong binary.
line "make (clean|all)"
make -C "$HERE" clean
make -C "$HERE" zerodir="$ZERODIR" all

# -C one level up so the archive unpacks as <name>/ rather than a pile of files. The tarball lands beside the project, not inside it, so it cannot pack itself.
line "tar package"
tar --exclude='__pycache__' --exclude='*.pyc' --exclude='*.pyo' \
    --exclude='.git' --exclude='error.log' \
    --exclude='profiles' --exclude='debug' \
    -czf "$OUT" -C "$(dirname "$PROJECT")" "$NAME"

# The one thing worth checking: the compiled parent is the reason this exists, and it is gitignored, so an exclude rule going wrong would be silent.
tar -tzf "$OUT" | grep -qx "$NAME/login/zero-login" ||
    { echo "error: the compiled binary did not make it into $OUT" >&2; exit 1; }
echo "- file: $OUT  ($(du -h "$OUT" | cut -f1))"
echo "- built for [$ZERODIR] - install.sh must be given a matching --prefix"
echo "- on the target: tar -xzf $NAME.tar.gz && sudo ./$NAME/login/install.sh"

# Copy, so the target is in one place and the key does the talking:
line "Copying to ben@n1"
scp "$OUT" ben@n1:~/
