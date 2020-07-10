#!/bin/bash

# Install the node_exporter binary from https://github.com/prometheus/node_exporter/releases/latest
# Only installs a specific version, not the latest.
# Default architecture is amd64. Can be changed by passing a parameter when calling the script.
# Only supports systemd-based distributions

ARCH=${1:-"amd64"}
VERSION="1.0.1"

BASE_TEMP_DIR=${XDG_RUNTIME_DIR:-"/var/run"}
TMPDIR="${BASE_TEMP_DIR}/install_node_exporter"
FILE_DEST="${TMPDIR}/node_exporter-${VERSION}.linux-${ARCH}.tar.gz"
SUMS_DEST="${TMPDIR}/sha256sums.txt"
FILE_URL="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/node_exporter-${VERSION}.linux-${ARCH}.tar.gz"
SUMS_URL="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/sha256sums.txt"
BIN_DEST="/usr/local/sbin/node_exporter"

function cleanup {
    echo "Cleaning up..."
    cd /
    rm ${FILE_DEST}
    rm ${SUMS_DEST}
    rmdir ${TMPDIR}
    if [ $? -ne 0 ]; then
        echo "Failed to delete temp dir ${TMPDIR}."
        exit 1
    fi

    echo "Bye!"
}

echo "Installing node_exporter v${VERSION}..."

if [ ! -d "$BASE_TEMP_DIR" ]; then
    echo "Attempted to use temp dir ${TMPDIR} but the parent doesn't exist. Bailing out..."
    exit 1
fi

mkdir ${TMPDIR}

if [ $? -ne 0 ]; then
    echo "Failed to create temp dir ${TMPDIR}. Bailing out..."
    exit 1
fi

cd ${TMPDIR}

echo "Downloading archive from ${FILE_URL}"
curl --tlsv1.2 -L ${FILE_URL} -o ${FILE_DEST}
if [ $? -ne 0 ]; then
    echo "Failed to download archive. Bailing out..."
    cleanup
    exit 1
fi

echo "Downloading checksums from ${SUMS_URL}"
curl --tlsv1.2 -L $SUMS_URL -o ${SUMS_DEST}
if [ $? -ne 0 ]; then
    echo "Failed to download checksums. Bailing out..."
    cleanup
    exit 1
fi

echo "Validating checksum..."
# --ignore-missing is not supported by Coreutils 8.22 (as appears in Amazon Linux 2 AMIs)
# sha256sum --check --ignore-missing ${SUMS_DEST}
grep `basename ${FILE_DEST}` ${SUMS_DEST} |  sha256sum --check -

if [ $? -ne 0 ]; then
    echo "Checksum verification failed. Bailing out..."
    cleanup
    exit 1
fi

echo "Unpacking archive..."
tar -xf ${FILE_DEST} node_exporter-${VERSION}.linux-${ARCH}/node_exporter

echo "Moving binary to ${BIN_DEST}"
mv ${TMPDIR}/node_exporter-${VERSION}.linux-${ARCH}/node_exporter ${BIN_DEST}
if [ $? -ne 0 ]; then
    echo "Moving binary failed. Bailing out..."
    cleanup
    exit 1
fi

echo "Creating systemd unit"
cat << EOF > /etc/systemd/system/node_exporter.service

[Unit]
Description=Node Exporter

[Service]
User=node_exporter
ExecStart=${BIN_DEST}

[Install]
WantedBy=multi-user.target
EOF

if [ $? -ne 0 ]; then
    echo "Creating unit file failed. Bailing out..."
    cleanup
    exit 1
fi

echo "Creating node_exporter user"
useradd --user-group --shell /sbin/nologin --system --no-create-home --home-dir /nonexistent node_exporter

echo "Activating unit"
systemctl daemon-reload
systemctl --now enable node_exporter.service

cleanup
exit 0
