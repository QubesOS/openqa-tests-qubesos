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
    my ($self) = @_;

    $self->select_gui_console;
    assert_screen "desktop";

    # try to start "Text Editor" (gedit)
    assert_and_click("menu");
    if (check_screen("menu-tab-favorites-active", 30)) {
        # switch to apps tab
        click_lastmatch();
    }
    assert_and_click("menu-vm-work");
    wait_still_screen();
    assert_and_click("menu-vm-text-editor");
    assert_screen("work-text-editor", timeout => 90);

    if (check_screen("text-editor-no-file-open-new", 5)) {
        click_lastmatch;
    }
    # ensure focus in on document content area
    if (check_screen("text-editor-area", 5)) {
        click_lastmatch;
    }
    type_string("https://www.qubes-os.org/\n");
    send_key("ctrl-a");
    send_key("ctrl-c");
    sleep(1);
    send_key("ctrl-shift-C");
    assert_screen("clipboard-copy-notification");
    die "nothing got copied" if (match_has_tag("clipboard-copy-0-bytes"));

    # try to start "Firefox" in personal
    assert_and_click("menu");
    if (check_screen("menu-tab-favorites-active", 30)) {
        # switch to apps tab
        click_lastmatch();
    }
    assert_and_click("menu-vm-personal");
    wait_still_screen();
    assert_and_click("menu-vm-firefox");
    assert_screen("personal-firefox", timeout => 120);

    # wait for full startup
    sleep(2);

    send_key("ctrl-shift-V");
    assert_screen("clipboard-paste-notification");
    # wait for firefox to fully start
    check_screen("firefox-bookmarks-bar", timeout => 20);
    assert_and_click("personal-firefox");
    sleep(1);
    send_key("ctrl-v");
    send_key("ret");
    assert_screen("qubes-website", timeout => 45);
    send_key("ctrl-q");
    if (check_screen("firefox-multitab-close", timeout => 30)) {
        assert_and_click("firefox-multitab-close");
    }
    wait_still_screen();


    # close the text editor too
    send_key("ctrl-q");
    # close without saving
    assert_and_click("text-editor-save-prompt");
    assert_screen("desktop");
}

sub post_fail_hook {
    my ($self) = @_;
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

