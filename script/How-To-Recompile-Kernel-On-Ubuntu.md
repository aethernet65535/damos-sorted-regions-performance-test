# Install Dependencies

```sh
sudo apt update
sudo apt install build-essential libncurses-dev bison flex libssl-dev libelf-dev fakeroot devscripts rsync
```

# Download the Kernel Source
```sh
mkdir ~/kernel-build && cd ~/kernel-build
apt-get source linux-image-unsigned-$(uname -r)

> [!NOTE]
> - Open the official Ubuntu sources file: `sudo vim /etc/apt/sources.list.d/ubuntu.sources`.
> - Look for the line starting with Types: `deb`` and change it to include `deb-src`

cd linux-*
```

# Configure the Kernel
```sh
cp /boot/config-$(uname -r) .config

scripts/config --disable SYSTEM_TRUSTED_KEYS
scripts/config --disable SYSTEM_REVOCATION_KEYS

make nconfig
```

# Compile the Kernel
```sh
make -j$(nproc) deb-pkg
```

# Install the Kernel
```sh
cd ..
sudo dpkg -i linux-image-*.deb linux-headers-*.deb
sudo update-grub
sudo reboot
```

# Verify the Change
```sh
uname -r
```
