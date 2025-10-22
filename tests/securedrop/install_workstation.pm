# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use base "installedtest";
use strict;
use testapi;
use networking;

sub download_repo {
    # Assumes terminal window is open
    # Assumes "curl_via_netvm"

    # Building SecureDrop Workstation RPM and installing it in dom0
    assert_script_run('sudo qubes-dom0-update -y make unzip');

    # Download source from git commit reference
    my $repo_archive_url = "https://github.com/freedomofpress/securedrop-workstation/archive/";
    assert_script_run("curl -f -L -o - $repo_archive_url" . get_var('GIT_REF') . '.zip > sdw.zip');
    assert_script_run('unzip sdw.zip');
    assert_script_run('mv securedrop-workstation-* securedrop-workstation');
};

# Following instructions at https://github.com/freedomofpress/securedrop-workstation-docs/blob/366c9c4/docs/admin/install/install.rst#download-securedrop-workstation-packages
sub qubes_contrib_keyring_bootstrap() {

    assert_script_run('sudo qubes-dom0-update -y qubes-repo-contrib', timeout => 120);

    # HACK: temporarily needed due to QubesOS/qubes-issues#10311
    assert_script_run('sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-qubes-4-contrib-fedora', timeout => 120);

    assert_script_run('sudo qubes-dom0-update --clean -y securedrop-workstation-keyring', timeout => 120);
    assert_script_run('sudo dnf -y remove qubes-repo-contrib');

    # HACK: temporarily needed due to QubesOS/qubes-issues#10310
    assert_script_run('systemd-run --on-active=5min rpm -e gpg-pubkey-d0941e87-5d8c9210');

};

sub install {
    my ($environment) = @_;

    download_repo();

    # Install prod keyring package through Qubes-contrib to simulate end-user
    # path, regardless of environment. This should be OK because staging / dev
    # packages will override any prod packages due to higher version numbers
    qubes_contrib_keyring_bootstrap();

    if ($environment eq "dev") {
        build_rpm();
    }


    # disable screen blanking during long command
    assert_script_run('env xset -dpms; env xset s off', valid => 0, timeout => 10);

    my $installation_cmd;
    if ($environment eq "prod") {
        sleep(15); # sleep for securedrop-workstation-keyring key to be imported
        assert_script_run("sudo qubes-dom0-update --clean -y securedrop-workstation-dom0-config");
        $installation_cmd = "sdw-admin --apply";
    } else {
        $installation_cmd = "cd securedrop-workstation && make $environment";
    }

    copy_config($environment);

    assert_script_run("$installation_cmd | tee /tmp/sdw-admin-apply.log",  timeout => 6000);
    upload_logs('/tmp/sdw-admin-apply.log', failok => 1);
};

sub copy_config {
    my ($environment) = @_;
    my $target_dir;
    my $sudo_modifier;

    if ($environment eq "prod") {
        # Place configuration files directly in final directory
        $target_dir = "/usr/share/securedrop-workstation-dom0-config";
        assert_script_run("sudo mkdir -p $target_dir");
        $sudo_modifier = "sudo "; # Tee command used later needs to run as root
    } else {
        # Place files in cloned repo (make targets will deal with the rest)
        $target_dir = "/home/user/securedrop-workstation";
        $sudo_modifier = "";  # no need for "sudo"
    }

    assert_script_run('echo "{\"submission_key_fpr\": \"65A1B5FF195B56353CC63DFFCC40EF1228271441\", \"hidserv\": {\"hostname\": \"bnbo6ryxq24fz27chs5fidscyqhw2hlyweelg4nmvq76tpxvofpyn4qd.onion\", \"key\": \"FDF476DUDSB5M27BIGEVIFCFGHQJ46XS3STAP7VG6Z2OWXLHWZPA\"}, \"environment\": \"' . $environment . '\", \"vmsizes\": {\"sd_app\": 10, \"sd_log\": 5}}" | ' . $sudo_modifier . 'tee ' . $target_dir . '/config.json');
    assert_script_run("curl https://raw.githubusercontent.com/freedomofpress/securedrop/d91dc67/securedrop/tests/files/test_journalist_key.sec.no_passphrase | $sudo_modifier tee $target_dir/sd-journalist.sec");


};


sub build_rpm {
    # Assumes terminal window is open


    assert_script_run('qvm-check sd-dev || qvm-create --label gray sd-dev --class StandaloneVM --template debian-12-xfce');

    # Building SecureDrop Workstation RPM and installing it in dom0
    assert_script_run('qvm-run -p sd-dev "sudo apt-get install -y make git jq"');
    assert_script_run('qvm-run -p sd-dev "git clone https://github.com/freedomofpress/securedrop-workstation"');
    assert_script_run('qvm-run -p sd-dev "git -C securedrop-workstation checkout ' . get_var('GIT_REF') . '"');

    # SecureDrop dev. env. according to https://developers.securedrop.org/en/latest/setup_development.html
    # DOCKER INSTALL according to https://docs.docker.com/engine/install/debian/
    assert_script_run('qvm-run -p sd-dev "sudo apt-get update"');
    assert_script_run('qvm-run -p sd-dev "sudo apt-get install -y ca-certificates curl"');
    assert_script_run('qvm-run -p sd-dev "sudo install -m 0755 -d /etc/apt/keyrings"');
    assert_script_run('qvm-run -p sd-dev "sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc"');
    assert_script_run('qvm-run -p sd-dev "sudo chmod a+r /etc/apt/keyrings/docker.asc"');
    assert_script_run('qvm-run -p sd-dev ". /etc/os-release && echo \"deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \$VERSION_CODENAME stable\" | sudo tee /etc/apt/sources.list.d/docker.list \> /dev/null"');
    assert_script_run('qvm-run -p sd-dev "sudo apt-get update"');
    assert_script_run('qvm-run -p sd-dev "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"');
    assert_script_run('qvm-run -p sd-dev "sudo groupadd docker || true"');
    assert_script_run('qvm-run -p sd-dev "sudo usermod -aG docker \$USER"');
    assert_script_run('qvm-shutdown --wait sd-dev && qvm-start sd-dev');  # Restart for groupadd to take effect

    # Also copy to dom0 to run tests later, but no need to configure env vars for future `make clone`.
    assert_script_run("qvm-run --pass-io sd-dev 'tar -c -C /home/user/ securedrop-workstation' | tar xvf -", timeout=>300);
    assert_script_run("ls");

    assert_script_run('qvm-run -p sd-dev "cd securedrop-workstation && make build-rpm"', timeout => 1000);
    assert_script_run("mkdir -p /home/user/securedrop-workstation/rpm-build/RPMS/noarch/");
    assert_script_run("qvm-run --pass-io sd-dev 'cat /home/user/securedrop-workstation/rpm-build/RPMS/noarch/*.rpm' > /home/user/securedrop-workstation/rpm-build/RPMS/noarch/sdw.rpm");
};


sub run {
    my ($self) = @_;

    $self->select_gui_console;
    assert_screen "desktop";

    x11_start_program('xterm');
    send_key('alt-f10');  # maximize xterm to ease troubleshooting

    curl_via_netvm;  # necessary for curling script and uploading logs

    assert_script_run('set -o pipefail'); # Ensure pipes fail

    install(get_var('SECUREDROP_ENV', 'dev'));

    send_key('alt-f4');  # close terminal
}

sub post_fail_hook {
    my $self = shift;

    $self->SUPER::post_fail_hook();

    upload_logs('/tmp/sdw-admin-apply.log', failok => 1);
};

1;

# vim: set sw=4 et:
