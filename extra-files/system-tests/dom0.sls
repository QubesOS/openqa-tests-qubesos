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

haveged:
  service.running:
    - enable: True
