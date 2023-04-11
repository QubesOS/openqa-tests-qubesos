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

sub run {
    my ($self) = @_;

    select_console('x11');
    assert_screen "desktop";
    x11_start_program("qvm-start windows-test", valid => 0);
    sleep(60);
    wait_still_screen;
    x11_start_program('xterm');
    assert_script_run("qubesd-query -e --fail -c /var/run/qubesd.internal.sock dom0 internal.SuspendPre dom0 && sleep 30 && qubesd-query -e --fail -c /var/run/qubesd.internal.sock dom0 internal.SuspendPost dom0", timeout => 90);
    assert_script_run("qvm-run -p windows-test 'cd'");
};

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { };
}


sub post_fail_hook {
    my $self = shift;

    $self->SUPER::post_fail_hook();
};

1;

# vim: set sw=4 et:
