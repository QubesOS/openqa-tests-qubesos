import subprocess
import os
from pathlib import Path

UPDATE_REPO_URL = "@REPO_URL@"
UPDATE_REPO_KEY = """@REPO_KEY@"""
ENABLE_TESTING = True
QUBES_VER = "@QUBES_VER@"
WHONIX_REPO = "@WHONIX_REPO@"

def testrepo(os_data, log, **kwargs):
    if os.path.exists("/usr/share/whonix/marker"):
        # Whonix randomizes time, sometimes setting it in the future, which breaks
        # at least Debian fasttrack
        subprocess.call(["date", "-s", "+5min"])

    if os_data["os_family"] == "Debian":
        with open('/etc/apt/sources.list.d/qubes-testing.list', 'w') as f:
            if ENABLE_TESTING:
                f.write(f"deb [arch=amd64 signed-by=/usr/share/keyrings/qubes-archive-keyring.gpg] https://deb.qubes-os.org/r{QUBES_VER}/vm {os_data['codename']}-testing main\n")
            if UPDATE_REPO_URL:
                f.write(f"deb [arch=amd64 signed-by=/usr/share/keyrings/test.gpg] {UPDATE_REPO_URL}/vm {os_data['codename']} main\n")
                subprocess.run(
                    ["gpg",
                     "--no-default-keyring",
                     "--keyring", "/usr/share/keyrings/test.gpg",
                     "--import"],
                    input=UPDATE_REPO_KEY.encode(),
                    check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif os_data["os_family"] == "RedHat":
        with open('/etc/yum.repos.d/qubes-testing.repo', 'w') as f:
            if ENABLE_TESTING:
                f.write("[qubes-testing]\n")
                f.write("name=qubes testing\n")
                f.write(f"baseurl=https://yum.qubes-os.org/r{QUBES_VER}/current-testing/vm/fc$releasever\n")
                f.write(f"gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-qubes-{QUBES_VER}-primary\n")
                f.write("gpgcheck = 1\n")
                f.write("repo_gpgcheck = 1\n")
            if UPDATE_REPO_URL:
                f.write("[test-repo]\n")
                f.write("name=test repo\n")
                f.write(f"baseurl={UPDATE_REPO_URL}/vm/fc$releasever\n")
                f.write(f"gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-test\n")
                f.write("gpgcheck = 1\n")
                f.write("repo_gpgcheck = 1\n")
                with open("/etc/pki/rpm-gpg/RPM-GPG-KEY-test", "w") as key_f:
                    key_f.write(UPDATE_REPO_KEY)
    elif os_data["os_family"] == "ArchLinux":
        with open('/etc/pacman.d/80-qubes-testing.conf', 'w') as f:
            if ENABLE_TESTING:
                f.write(f"[qubes-r{QUBES_VER}-current-testing]\n")
                f.write(f"Server = https://archlinux.qubes-os.org/r{QUBES_VER}/current-testing/vm/archlinux/pkgs\n")
            if UPDATE_REPO_URL:
                f.write("[qubes-test]\n")
                f.write(f"Server = {UPDATE_REPO_URL}/vm/archlinux\n")
                with open("/usr/share/pacman/keyrings/qubes-test.gpg", "w") as f:
                    f.write(UPDATE_REPO_KEY)
                list_output = subprocess.check_output([
                    "gpg", "--show-keys", "--with-colons", "--with-fingerprint",
                    "/usr/share/pacman/keyrings/qubes-test.gpg"
                ]).decode()
                key_fpr = [l for l in list_output.splitlines() if l.startswith("fpr:")][0].split(":")[9]
                with open("/usr/share/pacman/keyrings/qubes-test-trusted", "w") as f:
                    f.write(key_fpr + ":4:")
                with open("/usr/share/pacman/keyrings/qubes-test-revoked", "w") as f:
                    pass
                if not os.listdir('/etc/pacman.d/gnupg/private-keys-v1.d'):
                    subprocess.run("pacman-key", "--init", check=True)
                    subprocess.run("pacman-key", "--populate", check=True)
                else:
                    subprocess.run("pacman-key", "--populate", "qubes-test", check=True)
    if Path('/usr/share/whonix/marker').exists():
        subprocess.check_call([
            "repository-dist",
            "--enable",
            "--repository", 
            WHONIX_REPO])
