# JackTrip Raspberry Pi Image

```
# Clone pi-gen repository
git clone https://github.com/RPi-Distro/pi-gen.git

# Clone this repository as a subdirectory
cd pi-gen && git clone https://github.com/jacktrip/jacktrip-image.git

# Copy pi-gen config file
cp jacktrip-image/config .

# Apply patch to pi-gen stages
patch -p1 < jacktrip-image/pi-gen.patch

# Build image using a docker container
sudo ./build-docker.sh
```
