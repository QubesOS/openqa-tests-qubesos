# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2020 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
#
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
    my $state = 'qvm.sys-gui';
    my $vm = 'sys-gui';

    $self->select_gui_console;
    assert_screen "desktop";
    x11_start_program('xterm');
    send_key('alt-f10');
    become_root;
    curl_via_netvm;

    if (check_var('GUIVM_VNC', '1')) {
        $state = 'qvm.sys-gui-vnc';
        $vm = 'sys-gui-vnc';
    } elsif (check_var('GUIVM_GPU', '1')) {
        $state = 'qvm.sys-gui-gpu';
        $vm = 'sys-gui-gpu';
    }

    assert_script_run("qubesctl top.enable $state");
    assert_script_run("qubesctl top.enable $state pillar=True");

    assert_script_run('(set -o pipefail; qubesctl --all --show-output state.highstate 2>&1 | tee qubesctl-sys-gui.log)', timeout => 9000);
    upload_logs("qubesctl-sys-gui.log");

    # disable all states
    script_run('rm -f /srv/salt/_tops/base/*');

    # disable autostart until all tests modules can deal with it
    assert_script_run("qvm-prefs $vm autostart false");
    if (check_var('GUIVM_VNC', '1')) {
        # setup forwarding to sys-gui-vnc
        assert_script_run("echo qvm-connect-tcp 5900:\@default:5900 | qvm-run -pu root sys-net tee -a /rw/config/rc.local");
        assert_script_run("echo nft add rule ip qubes custom-input tcp dport 5900 accept | qvm-run -pu root sys-net tee -a /rw/config/rc.local");
        assert_script_run("echo qubes.ConnectTCP +5900 sys-net \@default allow target=sys-gui-vnc >> /etc/qubes/policy.d/30-user.policy");
    }

    type_string("exit\n");
    type_string("exit\n");
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { fatal => 1, milestone => 1 };
}


sub post_fail_hook {
    my $self = shift;

    $self->SUPER::post_fail_hook();
    upload_logs('/tmp/qubesctl-sys-gui.log', failok => 1);
};

1;

# vim: set sw=4 et:
