{% if grains['os'] == 'Debian' %}
python-apt:
  pkg.installed:
    - reload_modules: True
{% endif %}

{% if salt['pillar.get']('update:repo', '') %}

# FIXME: provide tor onion service for whonix

update-test:
  pkgrepo.managed:
    - humanname: udpate test
{% if grains['os'] == 'Fedora' %}
    - name: update-test
    - baseurl: {{ salt['pillar.get']('update:repo') }}/vm/fc{{ grains['osrelease'] }}
    - gpgkey: file:///etc/pki/rpm-gpg/update-test
    - gpgcheck: 0
{% elif grains['os'] == 'Debian' %}
    - key_url: salt://update/update-test.asc
    - name: deb http://{{ salt['pillar.get']('update:repo') }} {{ grains['oscodename'] }} main
    - file: /etc/apt/sources.list.d/update-test.list
    - require:
      - pkg: python-apt
{% endif %}

{% endif %}

repo-testing:
  pkgrepo.managed:
    - humanname: Qubes updates testing
    - disabled: False
{% if grains['os'] == 'Fedora' %}
    - name: qubes-testing
    - baseurl: http://yum.qubes-os.org/r4.0/current-testing/vm/fc{{ grains['osrelease'] }}
{% elif grains['os'] == 'Debian' %}
    - name: deb [arch=amd64] http://deb.qubes-os.org/r4.0/vm {{ grains['oscodename'] }}-testing main
    - file: /etc/apt/sources.list.d/qubes-r4.list
    - require:
      - pkg: python-apt
{% endif %}



{% if grains['os'] == 'Fedora' %}
/etc/pki/rpm-gpg/update-test:
  file.managed:
    - source: salt://update/update-test.asc
 
update-test-import:
  cmd.run:
    - name: rpm --import /etc/pki/rpm-gpg/update-test
    - unless: rpm -q gpg-pubkey-19f9875c
    - onchanges:
      - file: /etc/pki/rpm-gpg/update-test
{% endif %}

update:
  pkg.uptodate:
   - refresh: true
{% if grains['os'] == 'Debian' %}
   - dist_upgrade: True
{% endif %}
