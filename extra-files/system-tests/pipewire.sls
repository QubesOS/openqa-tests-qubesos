pipewire-pkgs:
  pkg.installed:
  - pkgs:
    - pipewire
    - pipewire-qubes
{% if grains['os'] == 'Debian' %}
#    - pipewire-pulse
{% else %}
    - pipewire-utils
    - pipewire-pulseaudio
{% endif %}

# workaround
/etc/qubes-rpc/qubes.PostInstall:
  cmd.run: []
