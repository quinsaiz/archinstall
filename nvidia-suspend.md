### /usr/local/bin/suspend-gnome-shell.sh:

```
#!/bin/bash

case "$1" in
    suspend)
        killall -STOP gnome-shell
        ;;
    resume)
        killall -CONT gnome-shell
        ;;
esac
```

### /etc/systemd/system/gnome-shell-suspend.service:

```
[Unit]
Description=Suspend gnome-shell
Before=systemd-suspend.service
Before=systemd-hibernate.service
Before=nvidia-suspend.service
Before=nvidia-hibernate.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/suspend-gnome-shell.sh suspend

[Install]
WantedBy=systemd-suspend.service
WantedBy=systemd-hibernate.service
```

### /etc/systemd/system/gnome-shell-resume.service:

```
[Unit]
Description=Resume gnome-shell
After=systemd-suspend.service
After=systemd-hibernate.service
After=nvidia-resume.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/suspend-gnome-shell.sh resume

[Install]
WantedBy=systemd-suspend.service
WantedBy=systemd-hibernate.service
```

### Then just enable the two new systemd units:

```
systemctl daemon-reload
systemctl enable gnome-shell-suspend
systemctl enable gnome-shell-resume
```

## Bash:

```
sudo install -Dm755 /dev/stdin /usr/local/bin/suspend-gnome-shell.sh <<'EOF'
#!/bin/bash
case "$1" in
    suspend) killall -STOP gnome-shell ;;
    resume)  killall -CONT gnome-shell ;;
esac
EOF

sudo install -Dm644 /dev/stdin /etc/systemd/system/gnome-shell-suspend.service <<'EOF'
[Unit]
Description=Suspend gnome-shell
Before=systemd-suspend.service systemd-hibernate.service
Before=nvidia-suspend.service nvidia-hibernate.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/suspend-gnome-shell.sh suspend

[Install]
WantedBy=systemd-suspend.service systemd-hibernate.service
EOF

sudo install -Dm644 /dev/stdin /etc/systemd/system/gnome-shell-resume.service <<'EOF'
[Unit]
Description=Resume gnome-shell
After=systemd-suspend.service systemd-hibernate.service
After=nvidia-resume.service nvidia-hibernate.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/suspend-gnome-shell.sh resume

[Install]
WantedBy=systemd-suspend.service systemd-hibernate.service
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now gnome-shell-suspend.service gnome-shell-resume.service
```
