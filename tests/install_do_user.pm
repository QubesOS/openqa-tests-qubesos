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
    assert_screen 'installer-main-ready';
    send_key 'f12';
    assert_and_click 'installer-install-hub-user';
    assert_screen 'installer-user';
    type_string 'user';
    send_key 'tab';
    type_string $password;
    send_key 'tab';
    type_string $password;
    send_key 'f12';
    assert_screen 'installer-user-weak-pass';
    send_key 'f12';
    assert_screen 'installer-install-user-created';
    assert_screen 'installer-post-install-tasks', 900;
    #assert_and_click 'installer-install-done-reboot', 'left', 600;
    assert_screen 'installer-install-done-reboot', 900;
}

1;

# vim: set sw=4 et:
