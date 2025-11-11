# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2025 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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
use serial_terminal;


sub run {
    my ($self) = @_;

    $self->select_gui_console;

    assert_and_click('panel-user-menu');
    assert_and_click('panel-user-menu-logout');
    assert_and_click('panel-user-menu-confirm');

    assert_screen('login-prompt-user-selected');
    assert_and_click('login-prompt-session-type-menu');
    assert_and_click('login-prompt-session-type-i3');
    type_string $testapi::password;
    send_key 'ret';

    assert_screen(['desktop', 'i3-welcome'], timeout => 90);

    wait_still_screen();

    if (check_screen('i3-welcome', timeout => 30)) {
        send_key('ret');
        assert_screen('i3-config-default-mod');
        send_key('ret');
    }
    assert_screen('x11');
    set_var('MAXIMIZE_KEY', 'super-f');

    if (check_screen('i3-config-errors')) {
        click_lastmatch();
        wait_still_screen;
        send_key('shift-G');
        die "Errors in the i3 config"
    }
}

sub post_fail_hook {
    my ($self) = @_;
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

