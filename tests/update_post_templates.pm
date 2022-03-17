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

    select_console('x11');
    assert_screen "desktop";
    x11_start_program('xterm');
    send_key('alt-f10');
    become_root;
    curl_via_netvm;

    if (get_var("UPDATE")) {
        assert_script_run('qubesctl top.enable update');
    }
    if (get_var("SALT_SYSTEM_TESTS")) {
        assert_script_run('qubesctl top.enable system-tests');
    }
    my @templates = split / /, get_var("UPDATE_TEMPLATES", "");
    foreach (@templates) {
        assert_script_run("(set -o pipefail; qubesctl --skip-dom0 --show-output --targets=$_ state.highstate 2>&1 | tee qubesctl-update.log)", timeout => 9000);
        # unlock the screen, if screenlocker engaged
        if (check_screen("screenlocker-blank")) {
            send_key('ctrl');
            assert_screen('xscreensaver-prompt', timeout=>5);
            type_password();
            send_key('ret');
        }
    }
    upload_logs("qubesctl-update.log");

    # disable all states
    script_run('rm -f /srv/salt/_tops/base/*');

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

