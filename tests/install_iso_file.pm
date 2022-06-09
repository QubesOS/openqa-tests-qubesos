# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2021 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

# /usr/bin/rpm is not included in the anaconda image :(
my $rpm_install = <<END;
#!/usr/bin/python3

import rpm
import os
import sys
import subprocess

t = rpm.ts()
pgpkey = subprocess.check_output(['gpg', '--output=-', '--dearmor', sys.argv[1]])
t.pgpImportPubkey(pgpkey)

for pkg in sys.argv[2:]:
    fd = os.open(pkg, os.O_RDONLY)
    h = t.hdrFromFdno(fd)
    # pass the FD as key_data to be returned by the callback below
    t.addInstall(h, fd, 'i')

def cb(reason, amount, total, key_data, client_data):
    if reason == rpm.RPMCALLBACK_INST_OPEN_FILE:
        os.lseek(key_data, 0, 0)
        return key_data
    
t.run(cb, None)
END

my $grub_cfg = <<END;
set timeout=3
set default=0

menuentry 'Qubes installation' {
    set isofile='(hd0,msdos1)/qubes.iso'
    loopback loop \\\$isofile
    multiboot2 (loop)/isolinux/xen.gz no-real-mode
    module2 (loop)/isolinux/vmlinuz inst.stage2=hd:LABEL=\$VOLID findiso=/dev/disk/by-uuid/\$DISK_UUID/qubes.iso iso-scan/filename=/qubes.iso
    module2 --nounzip (loop)/isolinux/initrd.img
}
END

sub run {
    if (check_var('UEFI', '1')) {
        die "UEFI not supported by this test";
    }
    # wait for bootloader to appear
    assert_screen 'bootloader', 30;

    # skip media verification
    send_key 'up';

    # press enter to boot right away
    send_key 'ret';

    # wait for the installer welcome screen to appear
    assert_screen 'installer', 300;

    select_console('root-virtio-terminal');

    if (!check_var("VERSION", "4.0")) {
        # enable network to download grub pkg
        assert_script_run("nmcli n on");
        assert_script_run("nmcli d connect \$(ls /sys/class/net|grep ^en)");
        assert_script_run("nm-online");
        my $grub2_url = 'https://archive.fedoraproject.org/pub/archive/fedora/linux/updates/32/Everything/x86_64/Packages/g/grub2-pc-modules-2.04-24.fc32.noarch.rpm';
        assert_script_run("curl -o grub2-pc-modules.rpm '$grub2_url'");
        type_string("cat >/tmp/rpm-install.py <<EOF\n${rpm_install}EOF\n", max_interval => 128);
        assert_script_run("python3 /tmp/rpm-install.py /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-32-primary grub2-pc-modules.rpm");
    }

    # create partition for the ISO file
    my $sfdisk_layout = "label: dos\n\n";
    $sfdisk_layout .= "type=83, bootable\n";
    assert_script_run("echo '$sfdisk_layout' | sfdisk /dev/?db");
    assert_script_run("mkfs.ext4 -F /dev/?db1");
    assert_script_run("mkdir /mnt/iso");
    assert_script_run("mount /dev/?db1 /mnt/iso");
    assert_script_run("cp /dev/sr0 /mnt/iso/qubes.iso", timeout => 180);
    assert_script_run("grub2-install --boot-directory=/mnt/iso /dev/?db", timeout => 180);

    # grub config
    assert_script_run("VOLID=\$(eval \$(blkid -o export /dev/sr0); echo \$LABEL)");
    assert_script_run("DISK_UUID=\$(eval \$(blkid -o export /dev/sdb1); echo \$UUID)");
    type_string("cat >/mnt/iso/grub2/grub.cfg <<EOF\n${grub_cfg}EOF\n", max_interval => 128);
    if (check_var("VERSION", "4.0")) {
        # older grub
        assert_script_run("sed -i -e 's:multiboot2:multiboot:' -e 's:module2:module:' /mnt/iso/grub2/grub.cfg");
    }
    assert_script_run("sync");
    assert_script_run("umount /mnt/iso");
    type_string("reboot -fn\n");
    select_console('installation', await_console=>0);
    reset_consoles();

    # requires BOOT_MENU=1
    assert_screen('boot-menu');
    send_key 'esc';
    send_key '2';
    # eject after reboot
    eject_cd();

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

1;

# vim: set sw=4 et:

