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

    if (!check_var('UEFI', '1')) {
        # wait for bootloader to appear
        assert_screen "bootloader", 90;

        if (match_has_tag("bootloader-installer")) {
            # troubleshooting
            send_key "down";
            send_key "ret";
            # boot from local disk
            send_key "down";
            send_key "down";
            send_key "down";
            send_key "ret";
        }
    }

    assert_screen "luks-prompt", 120;

    type_string "lukspass";

    send_key "ret";

    assert_screen "login-prompt-user-selected", 240;
    type_string "userpass";
    send_key "ret";

    assert_screen "desktop";
    select_console('root-virtio-terminal');
    assert_script_run "chown $testapi::username /dev/$testapi::serialdev";
    select_console('x11');
    wait_still_screen;
    # disable screensaver
    x11_start_program('killall xscreensaver', valid => 0);
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { fatal => 1, milestone => 1 };
}

sub post_fail_hook {
    my ($self) = @_;

    if (!testapi::is_serial_terminal) {
        send_key "esc";
        save_screenshot;
    }
    $self->SUPER::post_fail_hook;
}

1;

# vim: set sw=4 et:
