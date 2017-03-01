#APT_PROXY=localhost:3142
echo "Acquire::http { Proxy \"http://$APT_PROXY\"; };" > \
    /etc/apt/apt.conf.d/01proxy

# Update system time to avoid SSL errors later.
ntpdate-debian
service fake-hwclock stop

# dpkg: warning: unable to delete old directory '/lib/modules/3.18.7+/kernel/drivers/net/wireless': Directory not empty
rm /lib/modules/3.18.7+/kernel/drivers/net/wireless/8188eu.ko
# Prevent upgraded services from trying to start inside chroot.
echo exit 101 > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
DEBIAN_FRONTEND=noninteractive
# Remove Mopidy APT repo details, using pip version to avoid Wheezy induced dependency hell.
rm /etc/apt/sources.list.d/mopidy.list
apt-get update
apt-get remove --yes --purge python-pykka python-pylast

# Upgrade!
apt-get dist-upgrade -y

# https://github.com/pimusicbox/pimusicbox/issues/316
apt-get remove --yes --purge linux-wlan-ng
# https://github.com/pimusicbox/pimusicbox/issues/371
pip uninstall --yes mopidy-local-whoosh

# Need these to rebuild python dependencies
PYTHON_BUILD_DEPS="build-essential python-dev libffi-dev libssl-dev"
apt-get install --yes $PYTHON_BUILD_DEPS

rm -rf /tmp/pip_build_root
python -m pip install -U pip
# Upgrade some dependencies.
pip install requests[security] backports.ssl-match-hostname backports-abc tornado gmusicapi pykka pylast --upgrade
# The lastest versions that are still supported in Wheezy (Gstreamer 0.10).
pip install mopidy==1.1.2
# TODO: Update to v2.4.0 (when released)
pip install mopidy-musicbox-webclient==2.3.0
# TODO: Update to v0.5.0 (when released)
pip install https://github.com/pimusicbox/mopidy-websettings/zipball/develop
pip install mopidy-mopify==1.6.0
pip install mopidy-mobile==1.8.0
pip install mopidy-youtube==2.0.2
pip install mopidy-gmusic==2.0.0
pip install mopidy-spotify-web==0.3.0
pip install mopidy-spotify==1.4.0
pip install mopidy-tunein==0.4.1
pip install mopidy-local-sqlite==1.0.0
pip install mopidy-scrobbler==1.1.1

# Check everything except python and gstreamer is coming from pip.
mopidy --version
mopidy deps | grep "/usr/lib" | grep -v -e "GStreamer: 0.10" -e "Python: CPython" | wc -l

# Reckless hack for playlists not appearing issue.
sed -i '182s/^/#/' /usr/local/lib/python2.7/dist-packages/mopidy_spotify/session_manager.py

# Copy updated files.
if [ -d /tmp/filechanges ]; then
    cp -R /tmp/filechanges/* /
fi

# Clean up.
apt-get remove --yes --purge $PYTHON_BUILD_DEPS
apt-get autoremove --yes
apt-get clean
apt-get autoclean
rm -rf /var/lib/apt/lists/* /etc/apt/apt.conf.d/01proxy /usr/sbin/policy-rc.d /etc/dropbear/*key
find /var/log -type f | xargs rm
find /home/ -type f -name *.log | xargs rm
find /home/ -type f -name *_history | xargs rm