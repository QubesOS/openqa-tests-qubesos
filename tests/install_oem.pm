# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2023 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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
use serial_terminal;

my $ks_cfg = <<END;
#version=DEVEL
# Use graphical install
graphical
# clear disk
zerombr
# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'
# System language
lang en_US.UTF-8
# Network information
network  --hostname=dom0
# System timezone
timezone Europe/Berlin --utc
# X Window System configuration information
xconfig  --startxonboot
# System bootloader configuration
bootloader --location=mbr --boot-drive=sda
#Root password
rootpw --lock
# Disk partitioning information
ignoredisk --only-use=sda
autopart --type thinp --encrypted --passphrase="lukspass"

#reboot

%packages
@^qubes-xfce
%end

END

sub run {
    # TODO: check if really necessary:
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

    if (check_var("BACKEND", "qemu")) {
        # get console on hvc1 too
        select_console('install-shell');
        type_string("systemctl start anaconda-shell\@hvc1\n");
        select_console('installation', await_console=>0);
    }

    select_root_console();

    # create partition for the OEM install
    my $sfdisk_layout = 'label: gpt\n\n';
    $sfdisk_layout .= 'type=linux\n';
    assert_script_run("printf '$sfdisk_layout' | sfdisk /dev/?db", timeout => 60, max_interval => 100);
    assert_script_run("while ! [ -e /dev/?db1 ]; do sleep 1; done");
    assert_script_run("mkfs.ext4 -L QUBES_OEM -F /dev/?db1");
    assert_script_run("mkdir /mnt/oem");
    assert_script_run("mount /dev/?db1 /mnt/oem");

    type_string("cat >/mnt/oem/ks.cfg <<EOF\n${ks_cfg}EOF\n", max_interval => 128);
    assert_script_run("sync");
    assert_script_run("umount /mnt/oem");
    type_string("reboot -fn\n");
    select_console('installation', await_console=>0);
    reset_consoles();

    assert_screen('bootloader-oem');
    # press enter to boot right away
    send_key 'ret';

    assert_screen('installer-progress', timeout => 180);

    if (check_var("BACKEND", "qemu")) {
        # get console on hvc1 too
        select_console('install-shell');
        type_string("systemctl start anaconda-shell\@hvc1\n");
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

1;

# vim: set sw=4 et:

