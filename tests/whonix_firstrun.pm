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
    if (!check_screen('whonix-firstrun')) {
        # no firstrun wizard? maybe already accepted
        # TODO: add a variable to configure it and fail if the wizard was
        # expected
        record_soft_failure('No Whonix firstrun wizzard detected');
        return;
    }
    wait_still_screen;
    send_key('alt-n');
    assert_screen "whonix-connecting";
    assert_screen "whonix-connected";
}

1;

# vim: set sw=4 et:
