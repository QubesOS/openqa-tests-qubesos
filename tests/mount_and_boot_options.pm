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

sub run {
    my ($self) = @_;

    $self->select_gui_console;
    assert_screen "desktop";
    x11_start_program('xterm', match_typed => 'desktop-runner-xterm');
    send_key('alt-f10');
    script_run('mount');
    # expect discard option by default only in 4.0+
    if (get_var('VERSION') !~ /^3/) {
        if (script_run('mount | grep " / " | grep discard') ne 0) {
            record_soft_failure('discard option missing on root filesystem');
        }
    }
    script_run('xl info');
    if (script_run('xl info | grep ^xen_commandline | grep ucode=scan') ne 0) {
        record_soft_failure('Xen ucode=scan option missing');
    }
    if (script_run('xl info | grep ^xen_commandline | grep smt=off') ne 0) {
        record_soft_failure('Xen smt=off option missing');
    }
    my $boot_mountpoint = '/boot';
    if (check_var('MACHINE', 'uefi') && check_var('UEFI_DIRECT', '1')) {
        $boot_mountpoint = '/boot/efi';
    }
    script_run('df -h');
    if (script_run("test \$(df -k --output=size $boot_mountpoint | tail -n 1) -gt \$[ 400 * 2**10 ]") ne 0) {
        record_soft_failure("$boot_mountpoint smaller than 400MB");
    }
    script_run('systemctl list-units --failed --no-legend --no-pager');
    if (script_run("test \$(systemctl list-units --failed --no-legend | wc -l) -eq 0") ne 0) {
        record_soft_failure("there are failed system services");
    }
    script_run('systemctl list-units --user --failed --no-legend --no-pager');
    if (script_run("test \$(systemctl list-units --user --failed --no-legend | wc -l) -eq 0") ne 0) {
        record_soft_failure("there are failed user services");
    }

    if (get_var('VERSION') != '4.0') {
        # 4.1 should have discard on luks enabled (if there is one)
        if (script_run("sudo dmsetup table|grep luks-") eq 0) {
            if (script_run("sudo dmsetup table|grep luks-|grep discard") ne 0) {
                record_soft_failure("LUKS does not have discard enabled");
            }
        }
    }
    type_string("exit\n");
    assert_screen "desktop";
}

1;

# vim: set sw=4 et:
