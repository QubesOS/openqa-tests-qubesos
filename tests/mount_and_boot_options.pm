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

    select_console('x11');
    assert_screen "desktop";
    x11_start_program('xterm');
    send_key('alt-f10');
    script_run('mount');
    # expect discard option by default only in 4.0+
    if (get_var('VERSION') !~ /^3/) {
        if (script_run('mount | grep " / " | grep discard') != 0) {
            record_soft_failure('discard option missing on root filesystem');
        }
    }
    script_run('xl info');
    if (script_run('xl info | grep ^xen_commandline | grep ucode=scan') != 0) {
        record_soft_failure('Xen ucode=scan option missing');
    }
    if (script_run('xl info | grep ^xen_commandline | grep smt=off') != 0) {
        record_soft_failure('Xen smt=off option missing');
    }
    type_string("exit\n");
}

1;

# vim: set sw=4 et:
