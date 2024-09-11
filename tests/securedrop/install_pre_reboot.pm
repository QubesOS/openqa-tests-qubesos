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

sub run {
    my ($self) = @_;

    $self->select_gui_console;
    assert_screen "desktop";

    # Enable "presentation mode" to prevent the screen from going dark
    assert_and_click('disable-screen-blanking-click-power-tray-icon');
    assert_and_click('disable-screen-blanking-click-presentation-mode');
    send_key('esc');

    x11_start_program('xterm');
    send_key('alt-f10');  # maximize xterm to ease troubleshooting

    curl_via_netvm;

    assert_script_run('set -o pipefail'); # Ensure pipes fail

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
    assert_script_run('echo {\"submission_key_fpr\": \"65A1B5FF195B56353CC63DFFCC40EF1228271441\", \"hidserv\": {\"hostname\": \"bnbo6ryxq24fz27chs5fidscyqhw2hlyweelg4nmvq76tpxvofpyn4qd.onion\", \"key\": \"FDF476DUDSB5M27BIGEVIFCFGHQJ46XS3STAP7VG6Z2OWXLHWZPA\"}, \"environment\": \"prod\", \"vmsizes\": {\"sd_app\": 10, \"sd_log\": 5}} | sudo tee /usr/share/securedrop-workstation-dom0-config/config.json');
    assert_script_run('curl https://raw.githubusercontent.com/freedomofpress/securedrop/d91dc67/securedrop/tests/files/test_journalist_key.sec.no_passphrase | sudo tee /usr/share/securedrop-workstation-dom0-config/sd-journalist.sec');
    assert_script_run('sdw-admin --validate');

    assert_script_run('env xset -dpms; env xset s off', valid => 0, timeout => 10); # disable screen blanking during long command
    assert_script_run('sdw-admin --apply | tee /tmp/sdw-admin-apply.log',  timeout => 2400);  # long timeout due to slow virt.
    upload_logs('/tmp/sdw-admin-apply.log');
    send_key('alt-f4');  # close terminal
}

1;

# vim: set sw=4 et:
