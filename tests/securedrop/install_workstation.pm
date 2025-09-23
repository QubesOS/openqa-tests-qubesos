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

sub install_staging {
    # Assumes terminal window is open

    # NOTE: These are done via qvm-run instead of gnome-terminal so that we
    # can know in case they failed.
    assert_script_run('qvm-run -p work -- gpg --keyserver hkps://keys.openpgp.org --recv-key "2359 E653 8C06 13E6 5295 5E6C 188E DD3B 7B22 E6A3"');
    assert_script_run('qvm-run -p work -- "gpg --armor --export 2359E6538C0613E652955E6C188EDD3B7B22E6A3 > securedrop-release-key.pub"');
    assert_script_run('qvm-run -p work -- sudo rpmkeys --import securedrop-release-key.pub');
    assert_script_run('qvm-run -p work -- "echo -e \"[sd]\nenabled=1\nbaseurl=https://yum-qa.securedrop.org/workstation/dom0/f37\nname=boostrap\"  | sudo tee /etc/yum.repos.d/securedrop-temp.repo"');
    assert_script_run('qvm-run -p work -- dnf download -y securedrop-workstation-dom0-config');
    assert_script_run('qvm-run -p work -- "rpm -Kv securedrop-workstation-dom0-config-*.rpm"');  # TODO confirm output is correct
    assert_script_run('qvm-run -p work -- "cat /home/user/securedrop-workstation-dom0-config-*.rpm" > securedrop-workstation.rpm');
    assert_script_run('sudo dnf -y install securedrop-workstation.rpm');

    # setup staging config.json
    assert_script_run('echo {\"submission_key_fpr\": \"65A1B5FF195B56353CC63DFFCC40EF1228271441\", \"hidserv\": {\"hostname\": \"bnbo6ryxq24fz27chs5fidscyqhw2hlyweelg4nmvq76tpxvofpyn4qd.onion\", \"key\": \"FDF476DUDSB5M27BIGEVIFCFGHQJ46XS3STAP7VG6Z2OWXLHWZPA\"}, \"environment\": \"staging\", \"vmsizes\": {\"sd_app\": 10, \"sd_log\": 5}} | sudo tee /usr/share/securedrop-workstation-dom0-config/config.json');
    assert_script_run('curl https://raw.githubusercontent.com/freedomofpress/securedrop/d91dc67/securedrop/tests/files/test_journalist_key.sec.no_passphrase | sudo tee /usr/share/securedrop-workstation-dom0-config/sd-journalist.sec');
    assert_script_run('sdw-admin --validate');

};

sub install_dev {
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
    assert_script_run("qvm-run --pass-io sd-dev 'cat /home/user/securedrop-workstation/rpm-build/RPMS/noarch/*.rpm' > /tmp/sdw.rpm");
    assert_script_run('sudo dnf -y install /tmp/sdw.rpm', timeout => 1000);

    # setup dev config.json
    assert_script_run('echo {\"submission_key_fpr\": \"65A1B5FF195B56353CC63DFFCC40EF1228271441\", \"hidserv\": {\"hostname\": \"bnbo6ryxq24fz27chs5fidscyqhw2hlyweelg4nmvq76tpxvofpyn4qd.onion\", \"key\": \"FDF476DUDSB5M27BIGEVIFCFGHQJ46XS3STAP7VG6Z2OWXLHWZPA\"}, \"environment\": \"dev\", \"vmsizes\": {\"sd_app\": 10, \"sd_log\": 5}} | sudo tee /usr/share/securedrop-workstation-dom0-config/config.json');
    assert_script_run('curl https://raw.githubusercontent.com/freedomofpress/securedrop/d91dc67/securedrop/tests/files/test_journalist_key.sec.no_passphrase | sudo tee /usr/share/securedrop-workstation-dom0-config/sd-journalist.sec');
    assert_script_run('sdw-admin --validate');

};

sub run {
    my ($self) = @_;

    $self->select_gui_console;
    assert_screen "desktop";

    x11_start_program('xterm');
    send_key('alt-f10');  # maximize xterm to ease troubleshooting

    curl_via_netvm;  # necessary for curling script and uploading logs

    assert_script_run('set -o pipefail'); # Ensure pipes fail\

    install_dev;

    assert_script_run('env xset -dpms; env xset s off', valid => 0, timeout => 10); # disable screen blanking during long command
    assert_script_run('sdw-admin --apply | tee /tmp/sdw-admin-apply.log',  timeout => 6000);  # long timeout due to slow virt.
    upload_logs('/tmp/sdw-admin-apply.log', failok => 1);

    send_key('alt-f4');  # close terminal
}

sub post_fail_hook {
    my $self = shift;

    $self->SUPER::post_fail_hook();

    upload_logs('/tmp/sdw-admin-apply.log', failok => 1);
};

1;

# vim: set sw=4 et:
