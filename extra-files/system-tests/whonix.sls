/etc/systemcheck.d/40_qubes_test.conf:
    file.managed:
        - source: salt://system-tests/whonix-test.conf
        - mode: 644
        - makedirs: True
