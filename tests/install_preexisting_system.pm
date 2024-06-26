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
    select_console('root-virtio-terminal');

    if (check_var('UEFI', '1')) {
        # specify partition type as UUID, because sfdisk in Qubes 4.0 doesn't
        # understand anything else yet
        my $sfdisk_layout = "label: gpt\n\n";
        $sfdisk_layout .= "size=2GiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4\n"; # "rescue"
        $sfdisk_layout .= "size=750MiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4\n"; # /boot
        $sfdisk_layout .= "size=1GiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B\n";
        $sfdisk_layout .= "size=1GiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4\n"; # placeholder
        $sfdisk_layout .= "type=0FC63DAF-8483-4772-8E79-3D69D8477DE4\n"; # LUKS
        assert_script_run("echo '$sfdisk_layout' | sfdisk /dev/?da");
        assert_script_run("mkfs.vfat /dev/?da3");
        # extra "Qubes ..." entry as a regression test for #7004
        assert_script_run("efibootmgr -v -c -L 'Qubes old' -d /dev/?da -p 3 -l /EFI/qubes/xen.efi");
    } else {
        # emulate PureOS partition layout
        my $sfdisk_layout = "label: dos\n\n";
        $sfdisk_layout .= "size=2GiB, type=83\n"; # "rescue"
        $sfdisk_layout .= "size=750MiB, type=83, bootable\n"; # /boot
        $sfdisk_layout .= "type=5\n";
        $sfdisk_layout .= "type=83\n"; # LUKS
        assert_script_run("echo '$sfdisk_layout' | sfdisk /dev/?da");
    }
    # make "rescue" filesystem broken as in PureOS installation,
    # to not ease anaconda's life (see bug #3050)
    assert_script_run("mkfs.ext4 -F -S /dev/?da1 600000");
    assert_script_run("mkfs.ext4 /dev/?da2");
    assert_script_run("cryptsetup luksFormat /dev/?da5 -q -l 64 /dev/urandom");
    assert_script_run("sync");
    type_string("reboot -fn\n");
    select_console('installation', await_console=>0);
    reset_consoles();
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

