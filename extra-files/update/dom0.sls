{% if salt['pillar.get']('update:repo', '') %}

/etc/yum.repos.d/update-test.repo:
  file.managed:
    - source: salt://update/update-test-dom0.repo
    - template: jinja

{% endif %}

/etc/yum.repos.d/qubes-dom0-testing.repo:
  file.managed:
    - source: salt://update/qubes-testing-dom0.repo

/etc/pki/rpm-gpg/update-test:
  file.managed:
    - source: salt://update/update-test.asc
 
update-test-import:
  cmd.run:
    - name: rpm --import /etc/pki/rpm-gpg/update-test
    - unless: rpm -q gpg-pubkey-19f9875c
    - onchanges:
      - file: /etc/pki/rpm-gpg/update-test


update:
  pkg.uptodate:
   - refresh: true