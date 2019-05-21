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

use base 'anacondatest';
use strict;
use testapi;

sub run {
    unless (check_var('INSTALL_TEMPLATES', 'all')) {
        wait_still_screen;
        assert_and_click 'installer-main-hub-software';
        if (index(get_var('INSTALL_TEMPLATES'), 'whonix') == -1) {
            assert_and_click 'installer-software-whonix';
	    }
        if (index(get_var('INSTALL_TEMPLATES'), 'debian') == -1) {
            assert_and_click 'installer-software-debian';
        }
        assert_and_click 'installer-software-done';
    }
    assert_screen 'installer-main-hub';
}

1;

# vim: set sw=4 et:
