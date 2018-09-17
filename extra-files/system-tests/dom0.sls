dom0-packages:
  pkg.installed:
    - pkgs:
      - rpm-sign
      - rpm-build
      - xdotool
      - haveged
      - grub2-xen
      - qubes-usb-proxy-dom0
      - syslinux
      - genisoimage
      - pulseaudio-utils

haveged:
  service.running:
    - enable: True
