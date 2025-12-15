import os
import subprocess
import time
import fcntl

def get_packages(dist, version):
    packages = [
        "createrepo_c" if dist != "Debian" else "createrepo-c",
        "dnsmasq",
        "python3-pip" if dist != "ArchLinux" else "python-pip",
        "python3-uinput",
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

    # workaround for https://github.com/QubesOS/qubes-issues/issues/9581
    with open("/etc/udev/rules.d/99-network-workaround.rules", "w") as f:
        f.write('SUBSYSTEM=="net", DRIVERS=="e1000e", RUN+="/usr/bin/ethtool -K $name sg off"\n')

    setup_dist_dir = "/usr/share/setup-dist/status-files"
    if os.path.exists(setup_dist_dir):
        with open(setup_dist_dir + "/setup-dist.skip", "w"):
            pass
    if os.path.exists("/etc/systemcheck.d/30_default.conf"):
        with open("/etc/systemcheck.d/50_tests.conf", "w") as f:
            f.write('systemcheck_unwanted_package="$(echo "$systemcheck_unwanted_package" | sed \'s/ python3-pip //g\')"\n')
            for pattern in (
                "kernel: RETBleed: WARNING:",
                # Apr 15 19:13:11 host dovecot[1284]: master: Warning: Time moved forwards by 3394423.774836 seconds - adjusting timeouts.
                "dovecot.*Time moved",
                # test-only, actual issues
                "augenrules.*failure 1",
                "auditd.*: Error receiving audit netlink packet",
                # Mar 14 05:36:03 host systemd-fsck[377]: Ignoring error.
                "systemd-fsck.* Ignoring error.",
                # Mar 14 05:36:03 host systemd-fsck[377]: fsck failed with exit status 8.
                # https://github.com/QubesOS/qubes-issues/issues/9840
                "fsck failed with exit status 8",
                "Failed to read /qubes-netvm-gateway6",
                "'qubesdb-read /qubes-netvm-gateway6' failed",
                "Direct firmware load for regulatory.db failed",
                "Failed to read /qubes-ip6",
                "'qubesdb-read /qubes-ip6' or 'qubesdb-read /qubes-gateway6' failed",
                # Nov 05 16:03:11 host memlockd[927]: Mapped file /lib/x86_64-linux-gnu/libgpg-error.so.0
                "memlockd.*libgpg-error.so.0",
            ):
                f.write(f'journal_ignore_pattern_add "{pattern}" 2>/dev/null || journal_ignore_patterns_list+=( "{pattern}" )\n')

    subprocess.call(["systemctl", "disable", "dnsmasq"],
                    stdin=subprocess.DEVNULL)

    if (
        os.path.exists("/usr/share/anon-gw-base-files/gateway")
        or os.path.exists("/usr/share/anon-ws-base-files/workstation")
    ):
        subprocess.call(["systemctl", "enable", "check-user-slice-on-shutdown.service"],
                        stdin=subprocess.DEVNULL)
