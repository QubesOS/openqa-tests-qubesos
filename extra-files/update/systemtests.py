import os
import subprocess
import time

def get_packages(dist, version):
    packages = [
        "createrepo_c" if dist == "RedHat" else "createrepo-c", # else: Debian
        "dnsmasq",
        "python3-pip",
        "qubes-gpg-split-tests",
        "xdotool",
        "gcc",
        "pulseaudio-utils",
        "git",
        "alsa-utils",
        "qubes-input-proxy-sender",
        "qubes-usb-proxy",
        "usbutils",
        "qubes-core-admin-client",
    ]
    if dist == "RedHat":
        packages += [
            "redhat-rpm-config",
            "python3-devel", # TODO: CentOS: python38-devel, python36-devel
            "nmap-ncat",
            "pipewire-utils",
        ]
    return packages

def systemtests(os_data, log, **kwargs):
    pkgs = get_packages(os_data["os_family"], None)
    environ = os.environ.copy()
    environ['DEBIAN_FRONTEND'] = 'noninteractive'
    if os_data["os_family"] == "Debian":
        for _ in range(5):
            try:
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
    else:
        assert False

    subprocess.call(["systemctl", "disable", "dnsmasq"],
                    stdin=subprocess.DEVNULL)
