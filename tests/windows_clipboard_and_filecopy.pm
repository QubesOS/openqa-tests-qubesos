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

sub open_website_paste_edge {
    assert_and_click("menu-vm-windows-Edge");

    if (check_screen("windows-Edge-complete-setup", timeout => 60)) {
        click_lastmatch();
        assert_and_click("windows-Edge-complete-setup-confirm");
        assert_and_click("windows-Edge-no-signin");
    } else {
        if (check_screen("windows-Edge-no-google-signin", timeout => 15)) {
            assert_and_click("windows-Edge-no-google-signin");
        }
        assert_and_click("windows-Edge-setup-no-import");
        my $profiling_disabled;
        if (check_screen("windows-Edge-no-profiling", timeout => 10)) {
            click_lastmatch();
            $profiling_disabled = 1;
        }
        assert_and_click("windows-Edge-complete-setup-confirm");
        if (!$profiling_disabled) {
            if (check_screen("windows-Edge-no-google", timeout => 10)) {
                click_lastmatch();
            }
            assert_and_click("windows-Edge-no-profiling");
            assert_and_click("windows-Edge-complete-setup-confirm-and-start");
        }
    }
    if (check_screen("gui-warning-large-window")) {
        assert_and_click("gui-warning-large-window");
    }

    send_key("ctrl-shift-v");
    assert_screen("clipboard-paste-notification");

    assert_and_click("windows-Edge-address-bar");
    send_key("ctrl-a");
    send_key("ctrl-v");
    send_key("ret");

    assert_screen("qubes-website");
    assert_and_click("windows-Edge-close");
}

sub open_website_paste_ie {
    assert_and_click("menu-vm-windows-IE");

    if (check_screen("windows-IE-complete-setup", timeout => 60)) {
        # click on "Your current settings"
        click_lastmatch();
        assert_and_click("windows-IE-complete-setup-confirm");
    }

    assert_and_click("windows-IE-address-bar");
    send_key("ctrl-shift-v");
    assert_screen("clipboard-paste-notification");

    send_key("ctrl-a");
    send_key("ctrl-v");
    send_key("ret");

    assert_screen("qubes-website");
    assert_and_click("windows-IE-close");
}


sub run {
    my ($self) = @_;
    my $notepad_has_autosave = 0;

    $self->select_gui_console;
    assert_screen "desktop";

    # workaround for https://github.com/QubesOS/qubes-issues/issues/9841\
    x11_start_program('qvm-start windows-test', valid => 0);
    sleep(30);
    wait_still_screen;
    if (check_screen("windows-networks-prompt", timeout => 20)) {
        click_lastmatch();
        if (match_has_tag("ENV-WIN7")) {
            assert_and_click("windows-networks-finalize", timeout => 90);
        }
        sleep(5);
    }

    # try to start File Explorer
    assert_and_click("menu");
    assert_and_click("menu-vm-windows-test");
    assert_screen("menu-vm-windows-scroll-down");
    move_to_lastmatch();
    sleep(10);
    if (match_has_tag("new-menu")) {
        mouse_click();
    }
    mouse_hide();
    sleep(1);
    assert_and_click("menu-vm-windows-Explorer");

    # FIXME: win7 shows it here; disabled because windows-networks-finalize
    # races against Explorer; the prompt will remain open, in the background
    #if (check_screen("windows-networks-prompt", timeout => 90)) {
    #    click_lastmatch();
    #    if (match_has_tag("ENV-WIN7")) {
    #        assert_and_click("windows-networks-finalize");
    #    }
    #    sleep(5);
    #}
    assert_screen(["windows-Explorer", "windows-Explorer-inactive"], timeout => 90);

    # win10 shows this prompt after launching Explorer
    if (check_screen("windows-networks-prompt", timeout => 20)) {
        click_lastmatch();
        if (match_has_tag("ENV-WIN7")) {
            assert_and_click("windows-networks-finalize", timeout => 90);
        }
        sleep(5);
    }
    assert_screen("windows-Explorer", timeout => 90);

    if (check_screen("gui-warning-large-window")) {
        assert_and_click("gui-warning-large-window");
    }

    # Disable OneDrive ads
    if (check_var('WINDOWS_VERSION', 'win11x64')) {
        send_key('meta');
        assert_screen('windows-menu');
        type_string('applications');
        assert_and_click('windows-apps-features');
        send_key('tab');
        send_key('tab');
        send_key('tab');
        type_string('onedrive');
        assert_and_click('windows-apps-onedrive');
        assert_and_click('windows-apps-uninstall');
        assert_and_click('windows-apps-uninstall-confirm');
        wait_still_screen;
        assert_and_click('windows-apps-close');
    }

    # increased timeout, because it may wait for the network setting to finalize
    assert_and_click("windows-Explorer-Documents", timeout => 60);
    assert_and_click("windows-Explorer-empty", button => 'right', mousehide => -1);
    assert_and_click("windows-Explorer-new", mousehide => 1);
    assert_and_click("windows-Explorer-new-text-file");
    if (check_screen("windows-Explorer-new-name-edit", timeout => 20)) {
        send_key("ret");
    }
    assert_and_click("windows-Explorer-new-text-file-created", timeout => 60, dclick => 1);
    if (check_screen("windows-dropbox-error", timeout => 60)) {
        # Error: "'URLSearchParams' is undefined
        # URL: https://login.live.com/oauths20_desktop.srf?loc=1033
        assert_and_click("windows-dropbox-error");
    }
    assert_screen("windows-Notepad");
    if (check_screen("windows-Notepad-autosave-notice", timeout => 10)) {
        click_lastmatch();
        $notepad_has_autosave = 1;
    }

    type_string("https://www.qubes-os.org/\n");
    send_key("ctrl-a");
    send_key("ctrl-c");
    send_key("ctrl-shift-c");
    assert_screen("clipboard-copy-notification");

    # try to start "Firefox" in personal
    assert_and_click("menu");
    assert_and_click("menu-vm-personal");
    assert_and_click("menu-vm-firefox");
    assert_screen("personal-firefox", timeout => 120);

    # wait for full startup
    sleep(2);

    send_key("ctrl-shift-v");
    assert_screen("clipboard-paste-notification");
    # wait for firefox to fully start
    check_screen("firefox-bookmarks-bar", timeout => 20);
    assert_and_click("personal-firefox");
    # "New! Summarize pages in one click"
    if (check_screen("firefox-ai-prompt", timeout => 30)) {
        click_lastmatch;
        assert_and_click("personal-firefox");
    }
    send_key("ctrl-v");
    send_key("ret");
    assert_screen("qubes-website");
    send_key("ctrl-q");

    if (check_screen("firefox-multitab-close", timeout => 15)) {
        assert_and_click("firefox-multitab-close");
    }
    wait_still_screen();

    if ($notepad_has_autosave) {
        # this isn't really "autosave"; it saves somewhere, but not into the
        # original file!
        # do normal save explicitly
        send_key("ctrl-s");
    }

    # close the text editor too
    assert_and_click("windows-Notepad-file-menu", mousehide => -1);
    assert_and_click("windows-Notepad-file-exit", mousehide => 1);
    if (!$notepad_has_autosave) {
        assert_screen("windows-Notepad-save-prompt");
        # close with saving
        send_key("alt-s");
    }

    # now copy the file
    assert_and_click("windows-Explorer-new-text-file-created", button => 'right');
    if (check_screen("windows-Explorer-file-more-options", timeout => 10)) {
        click_lastmatch();
    }
    assert_and_click("windows-Explorer-file-send-to", mousehide => -1);
    assert_and_click("windows-Explorer-file-send-to-other-vm", mousehide => 1);
    assert_screen("file-copy-prompt");
    type_string("personal");
    # wait for anti-clickjacking grace period to pass
    sleep(1);
    send_key("ret");

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
    # close the text editor
    send_key("ctrl-q");
    assert_screen("files-new-text-document-selected");
    # and "Files" too
    send_key("ctrl-q");


    assert_and_click("menu");
    assert_and_click("menu-vm-windows-test");
    if (check_screen("menu-vm-windows-scroll-down", timeout => 30)) {
        move_to_lastmatch();
        sleep(10);
        if (match_has_tag("new-menu")) {
            mouse_click();
        }
        mouse_hide();
        sleep(1);
    }
    if (check_screen("menu-vm-windows-Edge", timeout => 30)) {
        open_website_paste_edge;
    } elsif (check_screen("menu-vm-windows-IE", timeout => 30)) {
        open_website_paste_ie;
    } elsif (check_screen("menu-vm-windows-Explorer")) {
        # no known browser, but Windows Explorer is visible; scroll one screen up and retry
        send_key("right");
        send_key("end");
        send_key("pageup");
        send_key("pageup");
        if (check_screen("menu-vm-windows-Edge", timeout => 30)) {
            open_website_paste_edge;
        } elsif (check_screen("menu-vm-windows-IE", timeout => 30)) {
            open_website_paste_ie;
        } else {
            die "no browser found in windows-test";
        }
    } else {
        die "no browser found in windows-test";
    }

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

