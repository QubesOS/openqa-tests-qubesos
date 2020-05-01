{% if grains['osrelease'] == '4.0' %}
{% set basedist = 'fc25' %}
{% elif grains['osrelease'] == '4.1' %}
{% set basedist = 'fc32' %}
{% else %}
{% set basedist = 'unknown' %}
{% endif %}

{% if salt['pillar.get']('update:repo', '') %}

/etc/yum.repos.d/update-test.repo:
  file.managed:
    - order: 10
    - source: salt://update/update-test-dom0.repo
    - template: jinja
    - context:
        basedist: {{basedist}}

{% endif %}

/etc/yum.repos.d/qubes-dom0-testing.repo:
  file.managed:
    - order: 10
    - source: salt://update/qubes-testing-dom0.repo
    - template: jinja
    - context:
        basedist: {{basedist}}

/etc/pki/rpm-gpg/update-test:
  file.managed:
    - order: 11
    - source: salt://update/update-test.asc
 
update-test-import:
  cmd.run:
    - order: 12
    - name: rpm --import /etc/pki/rpm-gpg/update-test
    - unless: rpm -q gpg-pubkey-19f9875c
    - onchanges:
      - file: /etc/pki/rpm-gpg/update-test

update:
  pkg.uptodate:
   - refresh: true

{% if salt['pillar.get']('update:repo', '') %}
# since the repo may not be available at later time, disable it here
disable-update-test:
  file.absent:
    - name: /etc/yum.repos.d/update-test.repo
    - require:
      - pkg: update
{% endif %}
