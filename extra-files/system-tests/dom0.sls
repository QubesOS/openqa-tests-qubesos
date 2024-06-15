dom0-packages:
  pkg.installed:
    - pkgs:
      - rpm-sign
      - rpm-build
      - xdotool
      - haveged
      - grub2-xen
      - grub2-xen-pvh
      - qubes-usb-proxy-dom0
      - syslinux
      - genisoimage
      - pulseaudio-utils
      - btrfs-progs
      - python3-nose2
      - python3-objgraph
      - patch
      - qubes-video-companion-dom0
{% if grains['osrelease'] != '4.1' %}
      - xinput
{% endif %}
      - openssl
{% if salt['pillar.get']('update:aem', '') %}
      - anti-evil-maid
{% endif %}

haveged:
  service.running:
    - enable: True
