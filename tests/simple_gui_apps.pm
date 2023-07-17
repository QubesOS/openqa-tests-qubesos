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
        send_key_until_needlematch("menu-vm-settings", "up", 20, 5);
    }
    assert_and_click("menu-vm-settings");
    assert_and_click("vm-settings-applications", timeout => 60);
    assert_and_click("vm-settings-app-evince");
    send_key('end');
    check_screen("vm-settings-app-xterm", timeout => 8);
    send_key_until_needlematch("vm-settings-app-xterm", 'up', 20, 5);
    assert_and_click("vm-settings-app-add");
    # wait for xterm to really be added, because that moves entries on the left
    assert_screen("vm-settings-app-xterm-added");
    assert_and_click(["vm-settings-app-evince", "vm-settings-app-text-editor"]);
    send_key('end');
    # let it scroll...
    sleep(1);
    assert_and_click("vm-settings-app-text-editor");
    assert_and_click("vm-settings-app-add");
    assert_and_click(["vm-settings-app-evince", "vm-settings-app-start-qube"]);
    if (match_has_tag("vm-settings-app-start-qube")) {
        # if start qube was clicked, scroll to home to make evince ("Document Viewer") visible
        send_key('home');
    }
    # let is scroll maybe, if evince not selected, click it again...
    sleep(2);
    if (check_screen("vm-settings-app-evince", 5)) {
        click_lastmatch();
    }
    assert_and_click("vm-settings-app-add");
    if (check_screen("vm-settings-app-missing-firefox")) {
        # Debian has different desktop file name, add it again
        assert_and_click("vm-settings-app-firefox");
        assert_and_click("vm-settings-app-add");
    }
    assert_and_click("vm-settings-ok");
    assert_screen("desktop");

    # wait for menu to regenerate
    sleep(2);

    # now try to start "Document Viewer"
    assert_and_click("menu");
    assert_and_click("menu-vm-work");
    assert_and_click("menu-vm-evince");
    assert_screen("work-evince", timeout => 90);

    # wait for full startup
    sleep(2);
    send_key("ctrl-w");
    wait_still_screen();
    assert_screen("desktop-clear");
}

sub post_fail_hook {
    my ($self) = @_;
    select_console('x11');
    send_key('esc');
    send_key('esc');
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

