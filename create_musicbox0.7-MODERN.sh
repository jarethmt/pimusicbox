MIN_FREE_SPACE_KB=$(expr 1024 \* 1024)
PIMUSICBOX_FILES=/tmp/filechanges
SHAIRPORT_VERSION=3.3.9
LIBRESPOT_VERSION=v20180529-1e69138

FREE_SPACE=$(df | awk '$NF == "/" { print $4 }')
if [ $FREE_SPACE -lt $MIN_FREE_SPACE_KB ]; then
    echo "************************************************"
    echo "** ERROR: Insufficient free space to upgrade  **"
    echo "** Use ./makeimage.sh bigger <image_file>     **"
    echo "************************************************"
    exit 3
fi

cd /tmp

# Update system time to avoid SSL errors later.
apt-get install ntpdate --yes --allow-unauthenticated
ntpdate-debian
service fake-hwclock stop
apt-get install --yes --allow-unauthenticated apt-transport-https

# Things we no longer need:
# * Favourite streams now implemented with playlists.
rm -f /boot/config/streamuris.js
# * Device Tree now properly handles all this stuff. Revert to upstream versions.
rm -f /etc/modules /etc/modprobe.d/*
# * Avahi support now included in Raspbian. Revert to upstream versions.
rm -rf /etc/avahi/*
# * Revert to upstream shairport-sync systemV script.
rm -f /etc/init.d/shairport-sync
# * Upgraded musicbox distro files.
rm -rf /opt/musicbox /opt/shairport-sync /opt/webclient /opt/defaultwebclient /opt/moped
# * dpkg: warning: unable to delete old directory '/lib/modules/3.18.7+/kernel/drivers/net/wireless': Directory not empty
rm -f /lib/modules/3.18.7+/kernel/drivers/net/wireless/8188eu.ko
# Remove Mopidy APT repo details, using pip version to avoid Wheezy induced dependency hell.
rm -f /etc/apt/sources.list.d/mopidy.list
rm -rf /etc/mopidy/extensions.d


##NEW way of installing upmpdcli
#apt-key adv --keyserver pool.sks-keyservers.net --recv-keys F8E3347256922A8AE767605B7808CE96D38B9201

mkdir ~/.gnupg/
chmod 700 ~/.gnupg
gpg --no-default-keyring --keyring /usr/share/keyrings/lesbonscomptes.gpg --keyserver keyserver.ubuntu.com --recv-key F8E3347256922A8AE767605B7808CE96D38B9201

cat << EOF > /etc/apt/sources.list.d/upmpdcli.list
deb [signed-by=/usr/share/keyrings/lesbonscomptes.gpg] http://www.lesbonscomptes.com/upmpdcli/downloads/raspbian/ buster main
deb-src [signed-by=/usr/share/keyrings/lesbonscomptes.gpg] http://www.lesbonscomptes.com/upmpdcli/downloads/raspbian/ buster main
EOF

apt-get update && apt-get install --yes upmpdcli

export DEBIAN_FRONTEND=noninteractive
apt-get update

# Fix locale
apt-get install --yes locales
echo "Europe/London" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata
sed -i -e 's/en_US.UTF-8 UTF-8/# en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i -e 's/# en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
echo -e 'LANG="en_GB.UTF-8"\nLANGUAGE="en_GB:en"' > /etc/default/locale
dpkg-reconfigure --frontend=noninteractive locales
update-locale LANG=en_GB.UTF-8

apt-get remove --yes --purge python-pykka python-pylast
# https://github.com/pimusicbox/pimusicbox/issues/316
apt-get remove --yes --purge linux-wlan-ng

# Ensure we reinstall the upstream config.
apt-get install --yes -o Dpkg::Options::="--force-confmiss" --reinstall avahi-daemon

# Get the packages required for setting wifi region
apt-get install --yes wireless-regdb crda

apt-get install --yes exfat-fuse

# Upgrade!
apt-get dist-upgrade --yes -o Dpkg::Options::="--force-confnew"

# Build and install latest version of shairport-sync
SHAIRPORT_BUILD_DEPS="build-essential xmltoman autoconf automake libdaemon-dev libasound2-dev libpopt-dev libconfig-dev libavahi-client-dev libssl-dev"
SHAIRPORT_RUN_DEPS="libc6 libconfig9 libdaemon0 libasound2 libpopt0 libavahi-common3 avahi-daemon libavahi-client3 libssl1.1 libtool avahi-daemon"
apt-get install --yes $SHAIRPORT_BUILD_DEPS $SHAIRPORT_RUN_DEPS
wget https://github.com/mikebrady/shairport-sync/archive/refs/tags/${SHAIRPORT_VERSION}.zip
unzip ${SHAIRPORT_VERSION}.zip && rm ${SHAIRPORT_VERSION}.zip
pushd shairport-sync-${SHAIRPORT_VERSION}
autoreconf -i -f
./configure --sysconfdir=/etc --with-alsa --with-avahi --with-ssl=openssl --with-metadata --with-systemv
make && make install
popd
rm -rf shairport-sync*

# Download and install Raspberry Pi Compatible ARMHF
mkdir -p /opt/librespot
pushd /opt/librespot
wget https://github.com/pimusicbox/librespot/archive/refs/tags/${LIBRESPOT_VERSION}/librespot-linux-armhf-raspberry_pi.zip
unzip librespot-linux-armhf-raspberry_pi.zip
rm librespot-linux-armhf-raspberry_pi.zip
popd

# Install mpd-watchdog (#224)
#wget https://github.com/pimusicbox/mpd-watchdog/releases/download/v0.3.0/mpd-watchdog_0.3.0-0tkem2_all.deb
#dpkg -i mpd-watchdog_0.3.0-0tkem2_all.deb
#rm mpd-watchdog_0.3.0-0tkem2_all.deb

# Need these to rebuild python dependencies
PYTHON_BUILD_DEPS="build-essential python3-dev python3-distutils libffi-dev libssl-dev libxml2-dev libxmlsec1-dev"
apt-get install --yes $PYTHON_BUILD_DEPS

rm -rf /tmp/pip_build_root
# Actually update pip from sources
curl https://bootstrap.pypa.io/get-pip.py | python3
# upgrade the rest
python3 -m pip install --upgrade setuptools
# Attempted workarounds for SSL/TLS issues in old Python version.
#pip3.7 install --upgrade certifi urllib3[secure] requests[security] backports.ssl-match-hostname backports-abc
# Upgrade some dependencies.
pip3.7 install --upgrade gmusicapi pykka pylast pafy youtube-dl
# The lastest versions that are still supported in Wheezy (Gstreamer 0.10).
pip3.7 install tornado==4.4
pip3.7 install mopidy==1.1.2
pip3.7 install mopidy-musicbox-webclient==2.5.0
pip3.7 install --no-deps --upgrade https://github.com/pimusicbox/mopidy-websettings/zipball/develop
pip3.7 install mopidy-websettings==0.2.3
pip3.7 install mopidy-mopify==1.6.1
pip3.7 install mopidy-mobile==1.8.0
pip3.7 install mopidy-youtube==2.0.2
pip3.7 install mopidy-gmusic==2.0.0
pip3.7 install mopidy-spotify-web==0.3.0
pip3.7 install mopidy-spotify-tunigo==1.0.0
pip3.7 install mopidy-spotify
# Custom version with Web API OAuth fix backported from v3.1.0
#pip3.7 install --no-deps --upgrade https://github.com/pimusicbox/mopidy-spotify/zipball/backport-oauth
pip3.7 install mopidy-tunein==0.4.1
pip3.7 install mopidy-local-sqlite==1.0.0
pip3.7 install mopidy-scrobbler==1.2.0
pip3.7 install mopidy-soundcloud==2.1.0
pip3.7 install mopidy-dirble==1.3.0
pip3.7 install mopidy-podcast==2.0.2
pip3.7 install mopidy-podcast-itunes==2.0.0
pip3.7 install mopidy-internetarchive==2.0.3
pip3.7 install mopidy-tidal==0.2.2

# https://github.com/pimusicbox/pimusicbox/issues/371
pip3.7 uninstall --yes mopidy-local-whoosh
pip3.7 uninstall --yes mopidy-podcast-gpodder.net
pip3.7 uninstall --yes mopidy-subsonic

# Check everything except python and gstreamer is coming from pip.
mopidy --version
mopidy deps | grep "/usr/lib" | grep -v -e "GStreamer: 0.10" -e "Python: CPython" | wc -l

# A bunch of reckless hacks:
# This should fix MPDroid trying to use MPD commands unsupported by Mopidy. But MPDroid still isn't working properly.
#sed -i 's/0.19.0/0.18.0/' /usr/local/lib/python2.7/dist-packages/mopidy/mpd/protocol/__init__.py
# Speedup MPD connections.
sed -i '/try:/i \
        # Horrible hack here:\
        core.library\
        core.history\
        core.mixer\
        core.playback\
        core.playlists\
        core.tracklist' /usr/local/lib/python2.7/dist-packages/mopidy/mpd/actor.py
# Force YouTube to favour m4a streams as gstreamer0.10's webm support is bad/non-existent:
sed -i '/getbestaudio(/getbestaudio(preftype="m4a"/' /usr/local/lib/python2.7/dist-packages/mopidy_youtube/backend.py
# Hide broken Spotify Web 'Genres & Moods' and 'Featured Playlists' browsing:
sed -i '222,+3 s/^/#/' /usr/local/lib/python2.7/dist-packages/mopidy_spotify_web/library.py
sed -i '222i ]' /usr/local/lib/python2.7/dist-packages/mopidy_spotify_web/library.py
# Hide broken Spotify Tunigo 'Genres & Moods', 'Featured Playlists' and 'Top Lists' browsing:
sed -i '27,+8 s/^/#/' /usr/local/lib/python2.7/dist-packages/mopidy_spotify_tunigo/library.py

cp -R $PIMUSICBOX_FILES/* /

deluser --remove-home mopidy
adduser --quiet --system --no-create-home --home /var/lib/mopidy --ingroup audio mopidy
chown -R mopidy:audio /var/cache/mopidy
chown -R mopidy:audio /var/lib/mopidy
chown -R mopidy:audio /var/log/mopidy
chown -R mopidy:audio /music/playlists

MUSICBOX_SERVICES="ssh dropbear upmpdcli shairport-sync mpd-watchdog"
for service in $MUSICBOX_SERVICES
do
    update-rc.d $service disable
done

# Update kernel as of 18/12/18 (4.14.89).
apt-get install --yes git rpi-update
PRUNE_MODULES=1 SKIP_WARNING=1 rpi-update d916c9b6b302356c7c250eb23a25236aeadb0375

# Very latest brcm wireless firmware
wget http://archive.raspberrypi.org/debian/pool/main/f/firmware-nonfree/firmware-brcm80211_20161130-3+rpt4_all.deb
dpkg -i firmware-brcm80211_20161130-3+rpt4_all.deb

# Remove unrequired packages (#426)
apt-get remove --purge --yes xserver-common x11-xkb-utils xkb-data libxkbfile1 \
    dpkg-dev groff-base libaspell15 libhunspell-1.3-0 man-db debian-reference-en \
    debian-reference-common libicu48 binutils cpp cpp-4.6 gcc-4.6-base gcc-4.7-base \
    libc-dev-bin libc6-dev make m4 autotools-dev git rpi-update

# Clean up.
apt-get remove --yes --purge $PYTHON_BUILD_DEPS $SHAIRPORT_BUILD_DEPS
apt-get autoremove --yes
apt-get clean
apt-get autoclean
