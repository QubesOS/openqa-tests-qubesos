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

use base "installedtest";
use strict;
use testapi;

sub run {
    my ($self) = @_;

    select_console('x11');
    x11_start_program('xterm');

    assert_script_run('qvm-create -l red runningvm');
    assert_script_run('qvm-start runningvm', timeout => 90);

    type_string("exit\n");
}

1;

# vim: set sw=4 et:
