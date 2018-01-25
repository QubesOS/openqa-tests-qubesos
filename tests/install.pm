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

use base 'basetest';
use strict;
use testapi;

sub run {
    if (!check_var('UEFI_DIRECT', '1')) {
        # wait for bootloader to appear
        assert_screen 'bootloader', 30;

        # skip media verification
        if (check_var('UEFI', '1')) {
            send_key 'down';
        } else {
            send_key 'up';
        }

        # press enter to boot right away
        send_key 'ret';
    }

    # wait for the desktop to appear
    assert_screen 'installer', 300;

    send_key 'f12';
    if (check_screen 'installer-unsupported-hardware' ) {
        assert_and_click 'installer-unsupported-hardware';
    }
    if (check_screen 'installer-prerelease' ) {
        assert_and_click 'installer-prerelease';
    }
    assert_screen 'installer-main-hub';
    assert_and_click 'installer-main-hub-target';
    assert_screen 'installer-disk-spoke';
    assert_and_click 'installer-done';
    assert_screen 'installer-disk-luks-passphrase';
    type_string 'lukspass';
    send_key 'tab';
    type_string 'lukspass';
    send_key 'ret';
    assert_screen 'installer-main-hub';
    unless (check_var('INSTALL_TEMPLATES', 'all')) {
    	assert_and_click 'installer-main-hub-software';
        if (index(get_var('INSTALL_TEMPLATES'), 'whonix') == -1) {
            assert_and_click 'installer-software-whonix';
	    }
        if (index(get_var('INSTALL_TEMPLATES'), 'debian') == -1) {
            assert_and_click 'installer-software-debian';
        }
        assert_and_click 'installer-software-done';
    }
    assert_screen 'installer-main-ready';
    send_key 'f12';
    assert_and_click 'installer-install-hub-user';
    assert_screen 'installer-user';
    type_string 'user';
    send_key 'tab';
    type_string 'userpass';
    send_key 'tab';
    type_string 'userpass';
    send_key 'f12';
    assert_screen 'installer-user-weak-pass';
    send_key 'f12';
    assert_screen 'installer-install-user-created';
    assert_screen 'installer-post-install-tasks', 900;
    #assert_and_click 'installer-install-done-reboot', 'left', 600;
    assert_screen 'installer-install-done-reboot', 600;
}

sub test_flags {
    # 'fatal'          - abort whole test suite if this fails (and set overall state 'failed')
    # 'ignore_failure' - if this module fails, it will not affect the overall result at all
    # 'milestone'      - after this test succeeds, update 'lastgood'
    # 'norollback'     - don't roll back to 'lastgood' snapshot if this fails
    return { fatal => 1 };
}

1;

# vim: set sw=4 et:
