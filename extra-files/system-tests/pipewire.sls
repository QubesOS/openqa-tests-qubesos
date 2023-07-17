{% if grains['os'] != 'Debian' or grains['osmajorrelease'] >= 12 %}
pipewire-pkgs:
  pkg.installed:
  - pkgs:
    - pipewire
    - pipewire-qubes
{% if grains['os'] == 'Debian' %}
    - pipewire-pulse
{% else %}
    - pipewire-utils
    - pipewire-pulseaudio
{% endif %}
{% endif %}

# workaround
/etc/qubes-rpc/qubes.PostInstall:
  cmd.run: []
