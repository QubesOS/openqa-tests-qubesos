{% if grains['oscodename'] == 'buster' %}
# https://bugs.debian.org/931566
accept-buster:
  cmd.run:
    - name: 'apt-get update --allow-releaseinfo-change'
{% endif %}

{% if grains['os'] == 'Gentoo' %}
emerge --sync:
  cmd.run: []
{% endif %}

vm-packages:
  pkg.installed:
    - refresh: True
{% if grains['os'] == 'Gentoo' %}
    - binhost: try
{% endif %}
    - pkgs:
{% if grains['os'] == 'Fedora' or grains['os'] == 'CentOS' %}
      - redhat-rpm-config
{% if grains['os'] == 'CentOS' %}
{% if grains['osmajorrelease'] == 8 %}
      - python38-devel
{% else %}
      - python36-devel
{% endif %}
{% else %}
      - python3-devel
{% endif %}
      - nmap-ncat
{% elif grains['os'] != 'Gentoo' %}
      - python3-cairo
      - libudev-dev
{% endif %}
{% if grains['os'] == 'Fedora' and grains['osmajorrelease'] >= 29 %}
      - createrepo_c
{% elif grains['os'] == 'CentOS' and grains['osmajorrelease'] >= 8 %}
      - createrepo_c
{% elif grains['os'] != 'Gentoo' %}
      - createrepo
{% endif %}
{% if grains['os'] == 'Gentoo' %}
      - virtual/libudev
      - dev-python/pycairo
      - dev-python/pip
      - app-emulation/qubes-gpg-split
      - app-emulation/qubes-input-proxy
      - app-emulation/qubes-usb-proxy
      - net-dns/dnsmasq
      - sys-apps/usbutils
      - x11-misc/xdotool
      - sys-devel/gcc
      - dev-vcs/git
      - media-sound/alsa-utils
{% else %}
      - dnsmasq
      - python3-pip
      - qubes-gpg-split-tests
      - xdotool
      - gcc
      - pulseaudio-utils
      - git
      - alsa-utils
      - qubes-input-proxy-sender
      - qubes-usb-proxy
      - usbutils
      - qubes-core-admin-client
{% endif %}

# do not autostart dnsmasq on Debian, it will conflict with the test
dnsmasq:
  service.disabled

# broken on Fedora 24, lets install using pip (tests will handle that)
python-uinput:
  pkg.removed: []
