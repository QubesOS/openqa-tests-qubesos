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
use utils qw(us_colemak);


sub run {
    if (check_var("VERSION", "4.1")) {
        setup_user();
    }
    assert_screen 'installer-main-ready';
    send_key 'f12';
    if (!check_var("VERSION", "4.1")) {
        setup_user();
    }

    my $timeout = 1500;
    if (check_var('INSTALL_TEMPLATES', 'all')) {
        $timeout += 4 * 240;
    }
    if (get_var('INSTALL_TEMPLATES', '') =~ /whonix/) {
        $timeout += 2 * 240;
    }
    if (get_var('INSTALL_TEMPLATES', '') =~ /debian/) {
        $timeout += 1 * 240;
    }
    assert_screen 'installer-post-install-tasks', $timeout;
    #assert_and_click 'installer-install-done-reboot', timeout => 600;
    assert_screen 'installer-install-done-reboot', 2200;
}

sub setup_user {
    assert_and_click 'installer-install-hub-user';
    assert_screen 'installer-user';
    if (check_var('KEYBOARD_LAYOUT', 'us-colemak')) {
        type_string us_colemak('user');
    } else {
        type_string 'user';
    }
    send_key 'tab';
    if (get_var('VERSION') =~ /^3/) {
        send_key 'tab';
    }
    if (check_var('KEYBOARD_LAYOUT', 'us-colemak')) {
        type_string us_colemak($password);
        send_key 'tab';
        type_string us_colemak($password);
    } else {
        type_string $password;
        send_key 'tab';
        type_string $password;
    }
    # let the password quality check process it
    sleep(1);
    send_key 'f12';
    assert_screen 'installer-user-weak-pass';
    send_key 'f12';
    assert_screen 'installer-install-user-created';
}

1;

# vim: set sw=4 et:
