import subprocess
from pathlib import Path

UPDATE_REPO_URL = "@REPO_URL@"
UPDATE_REPO_KEY = """@REPO_KEY@"""
ENABLE_TESTING = True
QUBES_VER = "@QUBES_VER@"
WHONIX_REPO = "@WHONIX_REPO@"

def testrepo(os_data, log, **kwargs):
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
    if Path('/usr/share/whonix/marker').exists():
        subprocess.check_call([
            "repository-dist",
            "--enable",
            "--repository", 
            WHONIX_REPO])
