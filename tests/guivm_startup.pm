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


sub run {
    select_console('x11');
    assert_screen "desktop";

    # FIXME: change to serial console, don't assume x11 session in dom0
    x11_start_program('xterm');
    assert_script_run("qvm-shutdown --all --wait", 180);
    assert_script_run("qubes-prefs default_guivm sys-gui");
    assert_script_run("qvm-start sys-firewall", 180);
    assert_script_run("! qvm-check sys-whonix || qvm-start sys-whonix", 90);
    type_string("exit\n");

    # start guivm
    x11_start_program('qvm-start sys-gui', target_match => 'sys-gui-window', match_timeout => 90);
    wait_still_screen();

    # make it fullscreen
    # FIXME: make guivm fullscreen by default
    wait_screen_change {
        send_key('alt-spc');
    };
    send_key('f');

    assert_screen "desktop";
}

sub post_fail_hook {
    my ($self) = @_;
    select_console('x11');
    send_key('esc');
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

