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
use serial_terminal qw(add_serial_console);

sub run {
    my ($self) = @_;

    select_console('root-virtio-terminal');
    open EXTRA_TARBALL, "tar cz -C " . testapi::get_required_var('CASEDIR') . " extra-files|base64|" or die "failed to create tarball";
    my $tarball = do { local $/; <EXTRA_TARBALL> };
    close(EXTRA_TARBALL);
    assert_script_run("echo '$tarball' | base64 -d | tar xz -C /mnt/sysimage/root");
    type_string "chroot /mnt/sysimage\n";
    type_string "cd /root/extra-files\n";
    type_string "python3 ./setup.py install\n";
    type_string "echo '$testapi::password' | passwd --stdin root\n";
    save_screenshot;
    type_string "exit\n";
    script_run "sed -ie s:console=none:console=vga,com1: /mnt/sysimage/boot/grub2/grub.cfg";
    script_run "sed -ie s:console=none:console=vga,com1: /mnt/sysimage/boot/efi/EFI/qubes/xen.cfg";
    type_string "sync\n";
    select_console('installation');
    #eject_cd;
    #power 'reset';
    assert_and_click 'installer-install-done-reboot';
    reset_consoles();
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { important => 1 };
}

1;
# vim: set sw=4 et ts=4:
