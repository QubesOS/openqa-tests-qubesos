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
use serial_terminal qw(select_root_console);


sub run {
    my ($self) = @_;
    select_root_console;

    $self->select_gui_console;

    # Update onion address
    x11_start_program('xterm');

    background_script_run("qvm-run -p sd-dev \"cd securedrop\; sed -i 's|/dev/stdout|/dev/null|g' securedrop/bin/dev-shell && make dev-tor\" </dev/null 2>&1 >/dev/null"); # | sed 's/^/[SD Server] /'"); # grep "journalist interface" so that it does not interfere with needles
    #assert_script_run("tail -f /tmp/securedrop-server.log | grep -m 1 '=> Journalist Interface <='", timeout => 90);
    # wait_serial("=> Journalist Interface <=");
    sleep(60); # wait for onion address to propagate

    # Update onion address
    x11_start_program('xterm');
    send_key('alt-f10');  # maximize xterm to ease troubleshooting
    assert_script_run('set -o pipefail'); # Ensure pipes fail\
    assert_script_run('export JOURNALIST_ONION=$(qvm-run -p sd-dev "sudo cat /var/lib/docker/volumes/sd-onion-services/_data/journalist/hostname")');
    assert_script_run('export JOURNALIST_KEY=$(qvm-run -p sd-dev "sudo cat /var/lib/docker/volumes/sd-onion-services/_data/journalist/authorized_clients/client.auth"| cut -d: -f3)');
    assert_script_run('sudo mkdir -p /usr/share/securedrop-workstation-dom0-config/');
    assert_script_run('echo {\"submission_key_fpr\": \"65A1B5FF195B56353CC63DFFCC40EF1228271441\", \"hidserv\": {\"hostname\": \"$JOURNALIST_ONION\", \"key\": \"$JOURNALIST_KEY\"}, \"environment\": \"prod\", \"vmsizes\": {\"sd_app\": 10, \"sd_log\": 5}} | sudo tee /usr/share/securedrop-workstation-dom0-config/config.json');
    type_string("cd /usr/bin && python3 -i sdw-admin --validate\n");
    type_string("copy_config()\n");
    sleep(1);
    send_key('ctrl-d');
    assert_script_run("sudo qubesctl --targets dom0 state.highstate || true", timeout => 1000);  # Reapply due to secrets change
}
1;
