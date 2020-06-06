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


sub run {
    select_console('x11');
    assert_screen "desktop";

    # open work VM settings and add "Document Viewer" application
    assert_and_click("menu");
    assert_and_click("menu-vm-work");
    if (!check_screen("menu-vm-settings")) {
        # "settings" entry doesn't fit on screen, scroll to it
        send_key("right");
        send_key_until_needlematch("menu-vm-settings", "up");
    }
    assert_and_click("menu-vm-settings");
    assert_and_click("vm-settings-applications");
    assert_and_click("vm-settings-app-evince");
    assert_and_click("vm-settings-app-add");
    assert_and_click("vm-settings-ok");
    assert_screen("desktop");

    # now try to start "Document Viewer"
    assert_and_click("menu");
    assert_and_click("menu-vm-work");
    assert_and_click("menu-vm-evince");
    assert_screen("work-evince", timeout => 90);

    # and close it
    wait_screen_change(sub {
        send_key("ctrl-q");
    });
    assert_screen("desktop");
}

sub post_fail_hook {
    my ($self) = @_;
    select_console('x11');
    send_key('esc');
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

