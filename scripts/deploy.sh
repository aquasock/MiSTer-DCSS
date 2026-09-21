#!/usr/bin/env bash
# Copies the bundle to the MiSTer over ssh.  Usage: MISTER_HOST=<ip> scripts/deploy.sh
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

HOST="${MISTER_HOST:?set MISTER_HOST to the IP address of the MiSTer}"
DEVICE_DIR="${DEVICE_DIR:-/media/fat/dcss}"
BUNDLE="$WORK/bundle"

# The MiSTer's stock login is root/1; feed it to ssh without sshpass.
ASKPASS="$WORK/askpass.sh"
printf '#!/bin/sh\necho 1\n' > "$ASKPASS"; chmod +x "$ASKPASS"
export SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force
SSH=(ssh -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no "root@$HOST")

# Replaces the program, data and level cache; keeps saves, morgues and any env.sh.
"${SSH[@]}" "mkdir -p $DEVICE_DIR && rm -rf $DEVICE_DIR/bin $DEVICE_DIR/dat $DEVICE_DIR/docs $DEVICE_DIR/settings $DEVICE_DIR/saves/db $DEVICE_DIR/saves/des"
tar -C "$BUNDLE/dcss" -cf - . | "${SSH[@]}" "tar --no-same-owner -C $DEVICE_DIR -xf -"
for f in "$BUNDLE"/Scripts/*.sh; do
    "${SSH[@]}" "mkdir -p /media/fat/Scripts && cat > /media/fat/Scripts/$(basename "$f") && chmod +x /media/fat/Scripts/$(basename "$f")" < "$f"
done
