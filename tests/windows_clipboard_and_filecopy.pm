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
use utils;


sub run {
    select_console('x11');
    assert_screen "desktop";

    # try to start File Explorer
    assert_and_click("menu");
    assert_and_click("menu-vm-windows-test");
    assert_screen("menu-vm-windows-scroll-down");
    move_to_lastmatch();
    sleep(10);
    mouse_hide();
    assert_and_click("menu-vm-windows-Explorer");
    assert_screen("windows-Explorer", timeout => 90);

    if (check_screen("windows-networks-prompt", timeout => 20)) {
        click_lastmatch();
        sleep(5);
    }

    assert_and_click("windows-Explorer-Documents");
    assert_and_click("windows-Explorer-empty", button => 'right');
    assert_and_click("windows-Explorer-new");
    assert_and_click("windows-Explorer-new-text-file");
    assert_screen("windows-Explorer-new-name-edit");
    assert_and_click("windows-Explorer-new-text-file-created", timeout => 60, dclick => 1);
    assert_screen("windows-Notepad");
    
    type_string("https://www.qubes-os.org/\n");
    send_key("ctrl-a");
    send_key("ctrl-c");
    send_key("ctrl-shift-c");
    assert_screen("clipboard-copy-notification");

    # try to start "Firefox" in personal
    assert_and_click("menu");
    assert_and_click("menu-vm-personal");
    assert_and_click("menu-vm-firefox");
    assert_screen("personal-firefox", timeout => 90);

    # wait for full startup
    sleep(2);

    send_key("ctrl-shift-v");
    assert_screen("clipboard-paste-notification");
    # wait for firefox to fully start
    check_screen("firefox-bookmarks-bar", timeout => 20);
    assert_and_click("personal-firefox");
    send_key("ctrl-v");
    send_key("ret");
    assert_screen("qubes-website");
    send_key("ctrl-q");
    if (check_screen("firefox-multitab-close", timeout => 8)) {
        assert_and_click("firefox-multitab-close");
    }
    wait_still_screen();

    # close the text editor too
    assert_and_click("windows-Notepad-file-menu");
    assert_and_click("windows-Notepad-file-exit");
    assert_screen("windows-Notepad-save-prompt");
    # close with saving
    send_key("alt-s");

    # now copy the file
    assert_and_click("windows-Explorer-new-text-file-created", button => 'right');
    assert_and_click("windows-Explorer-file-send-to");
    assert_and_click("windows-Explorer-file-send-to-other-vm");
    assert_screen("file-copy-prompt");
    type_string("personal");
    assert_and_click("file-copy-prompt-confirm");

    assert_and_click("menu");
    assert_and_click("menu-vm-personal");
    assert_and_click("menu-vm-Files");
    assert_and_click("files-qubesincoming", dclick => 1);
    assert_and_click("files-windows-test", dclick => 1);
    assert_and_click("files-new-text-document", dclick => 1);
    assert_screen("personal-text-editor", timeout => 90);
    send_key("ctrl-a");
    send_key("ctrl-c");
    send_key("ctrl-shift-c");
    assert_screen("clipboard-copy-notification");

    assert_and_click("menu");
    assert_and_click("menu-vm-windows-test");
    #assert_screen("menu-vm-windows-scroll-down");
    #move_to_lastmatch();
    #sleep(5);
    assert_and_click("menu-vm-windows-Edge");

    # close the text editor
    send_key("ctrl-q");
    assert_screen("files-new-text-document-selected");
    # and "Files" too
    send_key("ctrl-q");

    if (check_screen("windows-Edge-complete-setup", timeout => 60)) {
        click_lastmatch();
        assert_and_click("windows-Edge-complete-setup-confirm");
        assert_and_click("windows-Edge-no-signin");
    } else {
        assert_and_click("windows-Edge-setup-no-import");
        assert_and_click("windows-Edge-no-profiling");
        assert_and_click("windows-Edge-complete-setup-confirm");
    }

    send_key("ctrl-shift-v");
    assert_screen("clipboard-paste-notification");

    assert_and_click("windows-Edge-address-bar");
    send_key("ctrl-a");
    send_key("ctrl-v");
    send_key("ret");

    assert_screen("qubes-website");
    assert_and_click("windows-Edge-close");

    send_key("meta");
    assert_and_click("windows-menu-power");
    assert_and_click("windows-menu-shutdown");

    assert_screen("desktop");
}

sub post_fail_hook {
    my ($self) = @_;
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

