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

use base "basetest";
use strict;
use testapi;

sub run {
    my ($self) = @_;

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

    # press enter to boot right away
    send_key "ret";

    assert_screen "luks-prompt";

    type_string "lukspass";

    send_key "ret";

    assert_screen "firstboot-not-ready", 90;

    assert_and_click "firstboot-qubes";

    # TODO: check defaults, select various options

    send_key "f12";

    assert_screen "firstboot-configuring-templates", 90;
	
    my $timeout = 240;
    if (check_var('INSTALL_TEMPLATES', 'all')) {
        $timeout *= 4;
    }
    if (index(get_var('INSTALL_TEMPLATES', ''), 'whonix') != -1) {
        $timeout += 2 * 240;
    }
    if (index(get_var('INSTALL_TEMPLATES', ''), 'debian') != -1) {
        $timeout += 1 * 240;
    }
    assert_screen "firstboot-configuring-salt", $timeout;
    assert_screen "firstboot-setting-network", 240;
    assert_screen "firstboot-done", 240;
    send_key "f12";

    assert_screen "login-prompt-user-selected", 60;
    type_string "userpass";
    send_key "ret";

    assert_screen "desktop";
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { important => 1 };
}

1;

# vim: set sw=4 et:
