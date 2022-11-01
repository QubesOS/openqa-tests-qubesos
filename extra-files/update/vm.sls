{% set qubes_ver = salt['pillar.get']('update:qubes_ver', '') %}

{% if grains['oscodename'] == 'stretch' %}
# remove jessie-backports on debian template
/etc/apt/sources.list:
  file.line:
    - mode: delete
    - content: "https://deb.debian.org/debian jessie-backports main"
{% endif %}

{% if grains['oscodename'] == 'buster' %}
# https://bugs.debian.org/931566
'apt-get update --allow-releaseinfo-change':
  cmd.run:
   - order: 2
{% endif %}

{% if grains['id'].startswith('whonix-') %}
disable-whonix-onion:
  file.comment:
    - name: /etc/apt/sources.list.d/whonix.list
    - regex: '^.*dds6qkxpwdeubwucdiaord2xgbbeyds25rbsgr73tbfpqpt4a6vjwsyd'
    - onlyif:
      - test -e /etc/apt/sources.list.d/whonix.list

date -s +5min:
  cmd.run:
   - order: 1
{% endif %}


qubes-update-check.timer:
  service.dead: []
qubes-update-check.service:
  service.dead: []

{% if grains['os'] == 'Debian' %}
python3-apt:
  pkg.installed:
    - reload_modules: True
{% endif %}

{% if salt['pillar.get']('update:repo', '') %}

{% if grains['id'].startswith('whonix-') %}
{%   set update_repo = salt['pillar.get']('update:repo_onion', '') %}
{% else %}
{%   set update_repo = salt['pillar.get']('update:repo', '') %}
{% endif %}

update-test:
  pkgrepo.managed:
    - order: 5
    - humanname: update test
{% if grains['os'] == 'Fedora' %}
    - name: update-test
    - baseurl: {{ update_repo }}/vm/fc{{ grains['osrelease'] }}
    - gpgkey: file:///etc/pki/rpm-gpg/update-test
    - gpgcheck: 0
    - skip_if_unavailable: True
{% elif grains['os'] == 'CentOS' %}
    - name: update-test
    - baseurl: {{ update_repo }}/vm/centos{{ grains['osrelease'] }}
    - gpgkey: file:///etc/pki/rpm-gpg/update-test
    - gpgcheck: 0
    - skip_if_failure: True
{% elif grains['os'] == 'Debian' %}
    - key_url: salt://update/{{salt['pillar.get']('update:key', '19f9875c')}}.asc
    - name: deb {{ update_repo }}/vm {{ grains['oscodename'] }} main
    - file: /etc/apt/sources.list.d/update-test.list
    - require:
      - pkg: python3-apt
{% endif %}

{% endif %}

repo-testing:
  pkgrepo.managed:
    - order: 5
    - humanname: Qubes updates testing
    - disabled: False
{% if grains['os'] == 'Fedora' %}
    - name: qubes-testing
    - baseurl: https://yum.qubes-os.org/r{{ qubes_ver }}/current-testing/vm/fc{{ grains['osrelease'] }}
{% elif grains['os'] == 'CentOS' %}
    - name: qubes-testing
    - baseurl: https://yum.qubes-os.org/r{{ qubes_ver }}/current-testing/vm/centos{{ grains['osrelease'] }}
{% elif grains['os'] == 'Debian' %}
    - name: deb [arch=amd64] https://deb.qubes-os.org/r{{ qubes_ver }}/vm {{ grains['oscodename'] }}-testing main
    - file: /etc/apt/sources.list.d/qubes-r4.list
    - require:
      - pkg: python3-apt
{% endif %}


{% if grains['os'] == 'Debian' %}
# Workaround for https://github.com/saltstack/salt/issues/27067

/etc/apt/sources.list.d/qubes-r4.list:
  file.append:
    - text: deb [arch=amd64] https://deb.qubes-os.org/r{{ qubes_ver }}/vm {{ grains['oscodename'] }}-testing main

{% endif %}

{% if grains['id'].startswith('whonix-') %}
repository-dist --enable --repository {{salt['pillar.get']('update:whonix_repo', 'testers')}}:
  cmd.run: []
{% endif %}

{% if grains['os'] == 'Fedora' or grains['os'] == 'CentOS' %}
/etc/pki/rpm-gpg/update-test:
  file.managed:
    - source: salt://update/{{salt['pillar.get']('update:key', '19f9875c')}}.asc
 
update-test-import:
  cmd.run:
    - name: rpm --import /etc/pki/rpm-gpg/update-test
    - unless: rpm -q gpg-pubkey-{{salt['pillar.get']('update:key', '19f9875c')}}.asc
    - onchanges:
      - file: /etc/pki/rpm-gpg/update-test

dnf -y makecache:
  cmd.run: []
{% endif %}

update:
  pkg.uptodate:
   - refresh: True
{% if grains['os'] == 'Debian' %}
   - dist_upgrade: True
{% endif %}
{% if grains['os'] == 'Gentoo' %}
   - binhost: try
{% endif %}

notify-updates:
  cmd.run:
    - name: /usr/lib/qubes/upgrades-status-notify
    - success_retcodes:
      - 100

{% if salt['pillar.get']('update:repo', '') and grains['os'] == 'Debian' %}
# since the repo may not be available at later time, disable it here
disable-update-repo:
  pkgrepo.absent:
    - order: last
    - name: deb {{ update_repo }}/vm {{ grains['oscodename'] }} main
{% endif %}
