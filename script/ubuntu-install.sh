#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
  echo "please run as root"
  exit 1
fi

GRUB_FILE="/etc/default/grub"

echo "============================================================="
echo "DAMOS SORTED REGIONS PERFORMANCE TEST - UBUNTU INSTALL SCRIPT"
echo "============================================================="
echo ""

apt update
apt install -y \
sysstat \
build-essential \
libncurses-dev \
bison \
flex \
libssl-dev \
libelf-dev \
fakeroot \
devscripts \
rsync \
debhelper \
libdw-dev

# Check if psi=1 is already in GRUB_CMDLINE_LINUX_DEFAULT
if grep -q "psi=1" "$GRUB_FILE"; then
  echo "PSI is already enabled in $GRUB_FILE."
else
  echo "Enabling PSI in $GRUB_FILE..."
  # Backup grub file
  cp "$GRUB_FILE" "${GRUB_FILE}.bak"
  
  # Append psi=1 to GRUB_CMDLINE_LINUX_DEFAULT
  sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT=".*\)"/\1 psi=1"/' "$GRUB_FILE"
  
  # Update grub configs
  update-grub
  echo "GRUB updated successfully."
  read -p "A system reboot is required to activate PSI. Reboot now? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    reboot
  fi
fi

systemctl enable --now sysstat

echo "============="
echo "INSTALL: DONE"
echo "============="
