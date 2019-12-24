# Copyright © 2016-2017 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

package bootloader_setup;

use base Exporter;
use Exporter;

use strict;

use testapi;

our @EXPORT = qw(
  pre_bootmenu_setup
  stop_grub_timeout
  tianocore_enter_menu
  tianocore_select_bootloader
);

# choose boot device according to test variables; useful for booting from cdrom
# the second time, when the disk already contains some system
sub pre_bootmenu_setup {
    if (!get_var('UEFI') and check_var('BOOT_MENU', '1')) {
        assert_screen "boot-menu", 5;
        send_key('esc');
        assert_screen "boot-menu-select", 4;
        if (get_var("USBBOOT")) {
            send_key(3 + get_var("NUMDISKS"));
        } else {
            send_key(2 + get_var("NUMDISKS"));
        }
    }

    if (get_var("BOOT_HDD_IMAGE")) {
        assert_screen "grub2", 15;    # Use the same bootloader needle as in grub-test
        send_key "ret";               # boot from hd
        return 3;
    }
    return 0;
}

# prevent grub2 timeout; 'esc' would be cleaner, but grub2-efi falls to the menu then
# 'up' also works in textmode and UEFI menues.
sub stop_grub_timeout {
    send_key 'up';
}

sub tianocore_enter_menu {
    # press F2 and be quick about it
    send_key_until_needlematch('tianocore-mainmenu', 'f2', 15, 1);
}

sub tianocore_select_bootloader {
    tianocore_enter_menu;
    send_key_until_needlematch('tianocore-bootmanager', 'down', 5, 5);
    send_key 'ret';
}


