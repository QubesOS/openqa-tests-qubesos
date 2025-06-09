import os
import subprocess
import time
import fcntl

def get_packages(dist, version):
    packages = [
        "createrepo_c" if dist != "Debian" else "createrepo-c",
        "dnsmasq",
        "python3-pip" if dist != "ArchLinux" else "python-pip",
        "qubes-gpg-split-tests",
        "split-gpg2-tests",
        "xdotool",
        "gcc",
        "pulseaudio-utils" if dist != "ArchLinux" else "libpulse",
        "git",
        "alsa-utils",
        "qubes-input-proxy-sender" if dist != "ArchLinux" else "qubes-input-proxy",
        "qubes-usb-proxy",
        "usbutils",
        "qubes-core-admin-client",
        "qubes-audio-daemon",
        "qubes-video-companion",
        "fio",
    ]
    if dist == "RedHat":
        packages += [
            "redhat-rpm-config",
            "python3-devel", # TODO: CentOS: python38-devel, python36-devel
            "nmap-ncat",
            "pipewire-utils",
        ]
    if dist == "ArchLinux":
        packages += ("qubes-vm-dom0-updates",)
        packages += ("pipewire-audio",)  # pipewire-utils on Fedora
        packages.remove("qubes-gpg-split-tests") # not a separate package
        packages.remove("split-gpg2-tests") # not a separate package
        #packages.remove("qubes-core-admin-client") # not packaged yet
        packages.remove("qubes-audio-daemon") # not packaged yet
        packages.remove("qubes-video-companion") # not packaged yet
    return packages

def systemtests(os_data, log, **kwargs):
    pkgs = get_packages(os_data["os_family"], None)
    environ = os.environ.copy()
    environ['DEBIAN_FRONTEND'] = 'noninteractive'
    if os_data["os_family"] == "Debian":
        for _ in range(5):
            try:
                if os.path.exists("/var/lib/apt/lists/lock"):
                    with open("/var/lib/apt/lists/lock", "rb+") as lock_f:
                        fcntl.lockf(lock_f.fileno(), fcntl.LOCK_EX)
                subprocess.check_call(["apt-get", "update"],
                                      stdin=subprocess.DEVNULL,
                                      env=environ)
                break
            except subprocess.CalledProcessError as e:
                if e.returncode != 100:
                    raise
                time.sleep(5)
        else:
            raise Exception("Failed to 'apt-get update'")
        subprocess.check_call(["apt-get", "-y", "install"] + pkgs,
                              stdin=subprocess.DEVNULL,
                              env=environ)
    elif os_data["os_family"] == "RedHat":
        subprocess.check_call(["dnf", "-y", "install"] + pkgs,
                              stdin=subprocess.DEVNULL,
                              env=environ)
    elif os_data["os_family"] == "ArchLinux":
        subprocess.check_call(["pacman", "--noconfirm", "-Sy"] + pkgs,
                              stdin=subprocess.DEVNULL,
                              env=environ)
    else:
        assert False

    if os.path.exists("/etc/systemcheck.d/30_default.conf"):
        with open("/etc/systemcheck.d/50_tests.conf", "w") as f:
            f.write('systemcheck_unwanted_package="$(echo "$systemcheck_unwanted_package" | sed \'s/ python3-pip //g\')"\n')
            f.write('journal_ignore_pattern_add "kernel: RETBleed: WARNING:"\n')
            # Apr 15 19:13:11 host dovecot[1284]: master: Warning: Time moved forwards by 3394423.774836 seconds - adjusting timeouts.
            f.write('journal_ignore_pattern_add "dovecot.*Time moved"\n')
            # test-only, actual issues
            f.write('journal_ignore_pattern_add "augenrules.*failure 1"\n')
            f.write('journal_ignore_pattern_add "auditd.*: Error receiving audit netlink packet"\n')
            # Mar 14 05:36:03 host systemd-fsck[377]: fsck failed with exit status 8.
            # Mar 14 05:36:03 host systemd-fsck[377]: Ignoring error.
            # https://github.com/QubesOS/qubes-issues/issues/9840
            f.write('journal_ignore_pattern_add "fsck failed with exit status 8"\n')
            f.write('journal_ignore_pattern_add "systemd-fsck.* Ignoring error."\n')

    subprocess.call(["systemctl", "disable", "dnsmasq"],
                    stdin=subprocess.DEVNULL)
