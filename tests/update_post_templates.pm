# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2022 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

# install updates (as in updates.pm) on just installed extra template(s)

sub run {
    my ($self) = @_;

    $self->select_gui_console;
    assert_screen "desktop";
    x11_start_program('xterm');
    send_key('alt-f10');
    become_root;
    curl_via_netvm;

    assert_script_run("cp /root/extra-files/update/atestrepo.py /usr/lib/python3.*/site-packages/vmupdate/agent/source/plugins/");
    if (get_var("UPDATE")) {
        assert_script_run('qubesctl top.enable update');
    }
    if (get_var("SALT_SYSTEM_TESTS")) {
        assert_script_run('qubesctl top.enable system-tests');
        assert_script_run("cp /root/extra-files/update/systemtests.py /usr/lib/python3.*/site-packages/vmupdate/agent/source/plugins/");
    }
    my $targets = get_var('UPDATE_TEMPLATES', "");
    $targets =~ s/ /,/g;
    if (check_var("VERSION", "4.1")) {
        assert_script_run("(set -o pipefail; qubesctl --skip-dom0 --show-output --targets=$targets state.highstate 2>&1 | tee qubesctl-update.log)", timeout => 9000);
    } else {
        assert_script_run("script -c 'qubes-vm-update --force-update --log DEBUG --max-concurrency=2 --targets=$targets --show-output' -a -e qubesctl-update.log", timeout => 14400);
    }
    $self->maybe_unlock_screen;
    upload_logs("qubesctl-update.log");

    # disable all states
    script_run('rm -f /srv/salt/_tops/base/*');
    script_run('rm -f /usr/lib/python3.*/site-packages/vmupdate/agent/source/plugins/atestrepo.py');
    script_run('rm -f /usr/lib/python3.*/site-packages/vmupdate/agent/source/plugins/systemtests.py');


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
    upload_logs('/tmp/qubesctl-update.log', failok => 1);
};

1;

# vim: set sw=4 et:

