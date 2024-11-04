# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2024 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

    select_console("x11");
    assert_screen "desktop";
    x11_start_program("xterm");
    assert_script_run("grep s2idle /sys/power/mem_sleep");
    if (script_run("qvm-check sys-usb") == 0) {
        # those need to remain in dom0 for S0ix to work, they aren't real USB controllers anyway
        assert_script_run("qvm-shutdown --wait sys-usb; for dev in \$(qvm-pci ls | grep 'USB.*NHI' | cut -f 1 -d ' '); do qvm-pci dt sys-usb \$dev; done; qvm-start sys-usb");
        sleep(5);
        # let libinput know about the tablet
        mouse_hide;
    }
    assert_script_run('qvm-features dom0 suspend-s0ix 1');
    type_string("exit\n");
    assert_and_click("panel-user-menu");
    assert_and_click("panel-user-menu-logout");
    assert_and_click("panel-user-menu-reboot");

    # extra wait for shutdown, to align a bit with usual startup timeouts
    sleep(30);
    $self->handle_system_startup;

    select_console("x11");
    assert_screen "desktop";
    x11_start_program("xterm");
    assert_script_run("echo s2idle | sudo tee /sys/power/mem_sleep");
    type_string("exit\n");
}

1;

# vim: set sw=4 et:
