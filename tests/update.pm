# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2018 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

    select_console('x11');
    assert_screen "desktop";
    x11_start_program('xterm');
    send_key('alt-f10');
    become_root;
    curl_via_netvm;
    assert_script_run("curl " . autoinst_url('/assets/other/salt_state_update.tgz') . " >salt_state_update.tgz");
    assert_script_run('tar xf salt_state_update.tgz -C /srv/salt');
    assert_script_run('qubesctl top.enable update');
    
    # until QubesOS/qubes-issues#3655 got implemented
    assert_script_run('sed -i -e s:max_concurrency=4:max_concurrency=1: /usr/lib/python2.7/site-packages/qubessalt/__init__.py');
    assert_script_run('sed -i -e s:default=4:default=1: /usr/bin/qubesctl');
    # and another workaround
    assert_script_run('sed -i -e "s:\(qrexec_timeout.*default\)=60:\1=90:" /usr/lib/python3.5/site-packages/qubes/vm/qubesvm.py');
    assert_script_run('systemctl restart qubesd');
    assert_script_run('(set -o pipefail; qubesctl --templates --show-output state.highstate | tee qubesctl-upgrade.log)', timeout => 2400);
    assert_script_run('tail -1 qubesctl-upgrade.log|grep -v failed');
    assert_script_run('! grep ERROR qubesctl-upgrade.log');
    assert_script_run('! grep "^  Failed: *[1-9]" qubesctl-upgrade.log');
    upload_logs("qubesctl-upgrade.log");

    if (check_var('RESTART_AFTER_UPDATE', '1')) {
        type_string("reboot\n");
        assert_screen ["bootloader", "luks-prompt", "login-prompt-user-selected"], 300;
        $self->handle_system_startup;
    } else {
        type_string("exit\n");
        type_string("exit\n");
    }
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
    upload_logs('/tmp/qubesctl-upgrade.log', failok => 1);
};

1;

# vim: set sw=4 et:
