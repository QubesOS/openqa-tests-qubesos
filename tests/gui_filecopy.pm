# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2022 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

    type_string("https://www.qubes-os.org/\n");
    send_key("ctrl-s");
    assert_screen("file-save-dialog-home-dir");
    send_key("ctrl-a");
    type_string("test.txt");
    send_key("ret");
    sleep(1);
    # close editor
    send_key("ctrl-q");

    assert_and_click("menu");
    if (check_screen("menu-tab-favorites-active", 30)) {
        # switch to apps tab
        click_lastmatch();
    }
    assert_and_click("menu-vm-work");
    wait_still_screen();
    assert_and_click("menu-vm-Files");

    # copy to another VM
    assert_and_click("files-test-file", button => "right");
    # GTK is stupid and loads stylesheet _after_ showing the widget; it means
    # things will move around
    wait_still_screen();
    if (!check_screen("files-move-to-other", timeout => 5)) {
        # SUT has low resolution, if the menu doesn't fit, it gets a scrollbar - in
        # that case, try scrolling
        send_key("up");
        wait_still_screen();
    }
    assert_and_click("files-move-to-other");
    assert_screen("file-copy-prompt");
    type_string("personal");
    assert_and_click("file-copy-prompt-confirm");
    # wait for progress dialog to finish
    sleep(2);

    # verify, and then open in DispVM
    assert_and_click("menu");
    if (check_screen("menu-tab-favorites-active", 30)) {
        # switch to apps tab
        click_lastmatch();
    }
    assert_and_click("menu-vm-personal");
    wait_still_screen(stilltime => 10);
    assert_and_click("menu-vm-Files");
    assert_screen("personal-files", timeout => 90);
    assert_and_click("files-qubesincoming", dclick => 1);
    assert_and_click("files-work", dclick => 1);
    assert_and_click("files-test-file", button => "right");
    # GTK is stupid and loads stylesheet _after_ showing the widget; it means
    # things will move around
    wait_still_screen();
    if (!check_screen("files-open-in-dispvm", timeout => 5)) {
        # SUT has low resolution, if the menu doesn't fit, it gets a scrollbar - in
        # that case, try scrolling
        send_key("up");
        wait_still_screen();
    }
    assert_and_click("files-open-in-dispvm");
    assert_screen("disp-text-editor", timeout => 120);
    # verify content
    assert_screen("text-editor-qubes-url");
    send_key("ctrl-q");
    wait_still_screen();

    # then files in personal
    assert_and_click("personal-files");
    send_key("ctrl-q");
    wait_still_screen();

    # and in work
    assert_and_click("work-files");
    send_key("ctrl-q");
    wait_still_screen();

    assert_screen("desktop");
}

sub post_fail_hook {
    my ($self) = @_;
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

