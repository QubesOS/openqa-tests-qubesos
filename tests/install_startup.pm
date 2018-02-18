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
use bootloader_setup;

sub run {
    if (!check_var('UEFI', '1') or !check_var('UEFI_DIRECT', '1')) {
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
    if (check_var('UEFI', '1') and check_var('UEFI_DIRECT', '1')) {
        # in direct UEFI boot we enable /mapbs workaround, which crashes dom0
        # under OVMF
        tianocore_select_bootloader();
        send_key_until_needlematch('tianocore-menu-efi-shell', 'up', 5, 5);
        send_key 'ret';
        send_key 'esc';
        type_string "fs0:\n";
        type_string "EFI\\BOOT\\BOOTX64.efi qubes\n";
    }

    # wait for the installer welcome screen to appear
    assert_screen 'installer', 300;
}

sub test_flags {
    # 'fatal'          - abort whole test suite if this fails (and set overall state 'failed')
    # 'ignore_failure' - if this module fails, it will not affect the overall result at all
    # 'milestone'      - after this test succeeds, update 'lastgood'
    # 'norollback'     - don't roll back to 'lastgood' snapshot if this fails
    return { fatal => 1 };
}

sub post_fail_hook {

    # hide plymouth if any
    send_key "esc";
    save_screenshot;

};

1;

# vim: set sw=4 et:

