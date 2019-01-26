vm-packages:
  pkg.installed:
    - pkgs:
      - dnsmasq
{% if grains['os'] == 'Fedora' %}
      - redhat-rpm-config
      - python3-devel
      - nmap-ncat
{% else %}
      - python3-cairo
      - libudev-dev
{% endif %}
      - qubes-input-proxy-sender
      - qubes-gpg-split-tests
      - qubes-usb-proxy
      - qubes-usb-proxy
      - usbutils
{% if grains['os'] == 'Fedora' and grains['osmajorrelease'] >= 29 %}
      - createrepo_c
{% else %}
      - createrepo
{% endif %}
      - python3-pip
      - xdotool
      - gcc
      - pulseaudio-utils
      - git

# broken on Fedora 24, lets install using pip (tests will handle that)
python-uinput:
  pkg.removed: []
