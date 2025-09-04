# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2020 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

    assert_and_click("panel-user-menu");
    assert_and_click("panel-user-menu-logout");
    assert_and_click("panel-user-menu-confirm");

    assert_screen("login-prompt-user-selected");
    assert_and_click("login-prompt-session-type-menu");
    if (check_var("KDE_WAYLAND", "1")) {
        assert_and_click("login-prompt-session-type-kde-wayland");
    } else {
        assert_and_click("login-prompt-session-type-kde-x11");
    }
    type_string $testapi::password;
    send_key "ret";

    assert_screen(["desktop", "kde-welcome"], timeout => 90);

    wait_still_screen();

    if (check_screen("kde-welcome", timeout => 30)) {
        assert_and_click("kde-welcome");
    }
    assert_screen('x11');
    if (check_var("KDE_WAYLAND", "1")) {
        # Plasma started from lightdm(X11) on tty1 takes tty2:
        # https://github.com/sddm/sddm/issues/1409
        console("x11")->set_tty(2);
    }
}

sub post_fail_hook {
    my ($self) = @_;
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

