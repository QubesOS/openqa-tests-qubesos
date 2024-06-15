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

# WARNING: this test depends on simple_gui_apps.pm (which adds xterm to the menu)

sub run {
    x11_start_program('sh -c \'echo -e "timeout:\t0:02:00" > ~/.xscreensaver\'', valid => 0);
    if (check_var('KEEP_SCREENLOCKER', '1')) {
        x11_start_program('xscreensaver-command -restart', target_match => 'desktop-clear');
    } elsif (!check_var("DESKTOP", "kde")) {
        x11_start_program('xscreensaver -no-splash', target_match => 'desktop-clear');
    }
    assert_and_click("menu");
    if (check_screen("menu-tab-favorites-active", 30)) {
        # switch to apps tab
        click_lastmatch();
    }
    assert_and_click("menu-vm-work");
    assert_and_click("menu-vm-xterm");

    my $xterm_title_area = assert_screen('work-xterm')->{area}->[-1];

    my ($click_x, $click_y) = ($xterm_title_area->{x}, $xterm_title_area->{y}+100);
    mouse_set($click_x, $click_y);
    # now click every 10s but don't move!
    for (1..15) {
        mouse_click();
        sleep(10);
    }

    # clicking should prevent locking the screen
    assert_screen('work-xterm');
    type_string("exit\n");

    mouse_hide();
    assert_screen("desktop");
}

sub post_fail_hook {
    my ($self) = @_;
    $self->select_gui_console;
    save_screenshot;
    $self->SUPER::post_fail_hook;
};

1;

# vim: set sw=4 et:

