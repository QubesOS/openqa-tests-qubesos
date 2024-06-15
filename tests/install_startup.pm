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
use serial_terminal qw(select_root_console);

sub run {
    pre_bootmenu_setup();

    if (check_var('BACKEND', 'qemu')) {
        if (check_var('UEFI', '1')) {
            if (check_var('UEFI_DIRECT', '1')) {
                # grub2-efi can't load xen.efi on OVMF...
                # default direct xen.efi boot is also broken on OVMF - see below
                tianocore_select_bootloader();
                send_key_until_needlematch('tianocore-menu-efi-shell', 'up', 5, 5);
                send_key 'ret';
                send_key 'esc';
                type_string "fs0:\n";
                # in direct UEFI boot we enable /mapbs workaround, which crashes dom0
                # under OVMF - choose different boot option than default (qubes-verbose)
                type_string "EFI\\BOOT\\BOOTX64.efi qubes\n";
            } else {
                assert_screen 'bootloader', 30;
                if (check_var('KERNEL_VERSION', 'latest')) {
                    # verbose
                    send_key 'down';
                    # rescue
                    send_key 'down';
                    # kernel latest
                    send_key 'down';
                } else {
                    send_key 'up';
                }
                # press enter to boot right away
                send_key 'ret';
            }
        } else {
            # wait for bootloader to appear
            assert_screen 'bootloader', 30;

            # skip media verification
            if (check_var('KERNEL_VERSION', 'latest')) {
                if (check_var('VERSION', '4.1')) {
                    # isolinux menu
                    # troubleshooting
                    send_key 'down';
                    send_key 'ret';
                    assert_screen 'bootloader-troubleshooting';
                    # kernel latest
                    send_key 'down';
                } else {
                    # grub menu
                    # verbose
                    send_key 'down';
                    # rescue
                    send_key 'down';
                    # kernel latest
                    send_key 'down';
                }
            } else {
                send_key 'up';
            }

            # press enter to boot right away
            send_key 'ret';
        }
    } elsif (check_var('HEADS', '1')) {
        heads_boot_usb;
    }

    # wait for the installer welcome screen to appear
    assert_screen 'installer', 360;

    if (match_has_tag('installer-inactive')) {
        mouse_set(10, 10);
        mouse_click();
        mouse_hide();
    }

    if (check_var("BACKEND", "qemu")) {
        # get console on hvc1 too
        select_console('install-shell');
        type_string("systemctl start anaconda-shell\@hvc1\n");
        select_console('installation', await_console=>0);
    }

    if (check_var("MACHINE", "hw7") or check_var("MACHINE", "hw12")) {
        select_root_console();
        # RTC battery not connected
        script_run("date -s @" . time());
        script_run("hwclock -w");
        select_console('installation', await_console=>0);
    }
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

