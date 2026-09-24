#!/bin/bash

set -o pipefail

FILES=("deploymentclient.conf" "clear.sh")
HOSTS_FILE="hosts.txt"
REMOTE_USER="sysdba"
SRC_DIR="/opt/splunkforwarder/etc/system/local"
TMP_DIR="/tmp"
DEST_DIR="/opt/splunkforwarder/etc/system/local"
SERVICE_NAME="splunk"
TS=$(date +%F_%H%M%S)

for HOST in $(cat "$HOSTS_FILE"); do
    echo "========== $HOST =========="

    # 1. Kiểm tra service tồn tại
    if ! ssh "${REMOTE_USER}@${HOST}" "systemctl status ${SERVICE_NAME} >/dev/null 2>&1"; then
        echo "❌ Service ${SERVICE_NAME} not found on $HOST — skip"
        continue
    fi

    # 2 + 3. Backup + SCP local → remote /tmp
    for FILE in "${FILES[@]}"; do
        SRC_FILE="${SRC_DIR}/${FILE}"
        DEST_TMP="${TMP_DIR}/${FILE}"

        if [ ! -f "$SRC_FILE" ]; then
            echo "❌ Source file missing: $SRC_FILE"
            continue 2
        fi

        scp "$SRC_FILE" "${REMOTE_USER}@${HOST}:${DEST_TMP}" || {
            echo "❌ SCP failed: $FILE on $HOST"
            continue 2
        }
    done

    # 4 → 6 gom trong 1 phiên SSH
    ssh "${REMOTE_USER}@${HOST}" <<EOF
set -e

echo "→ Backup old files"
for f in ${FILES[*]}; do
    sudo cp -a "${DEST_DIR}/\$f" "${DEST_DIR}/\$f.${TS}.bak" 2>/dev/null || true
done

echo "→ chown"
sudo chown splunk:splunk ${TMP_DIR}/*.conf

echo "→ move"
sudo mv ${TMP_DIR}/deploymentclient.conf ${DEST_DIR}/

echo "Run script"
sudo chmod +x ${TMP_DIR}/clear.sh
sudo sh ${TMP_DIR}/clear.sh
EOF

    if [ $? -eq 0 ]; then
        echo "✅ Completed on $HOST"
    else
        echo "❌ Failed on $HOST"
    fi

    echo
done

