/usr/lib/qubes/xenstore-watch-trigger.py:
  file.managed:
    - source: salt://system-tests/xenstore-watch-trigger.py
    - mode: 0755

/lib/systemd/system/xenstore-watch-trigger.service:
  file.managed:
    - contents: |
        [Unit]
        Description=Workaround for xenstore watch VM problems
        After=xenstored.service
        
        [Service]
        Type=simple
        ExecStart=/usr/lib/qubes/xenstore-watch-trigger.py
        StandardOutput=syslog
        
        [Install]
        WantedBy=multi-user.target

systemctl daemon-reload:
  cmd.run:
    - runas: root
    - onchange:
      - file: /lib/systemd/system/xenstore-watch-trigger.service


xenstore-watch-trigger:
  service.running:
    - enable: True
