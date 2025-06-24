# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2024 Marta Marczykowska-Górecka <marmarta@invisiblethingslab.com>
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
    # open global-settings
    select_console('x11');
    assert_screen "desktop";
    x11_start_program('qubes-global-config');

    # try to go through all pages and see if they work
    assert_and_click('global-config-switch-to-usb');
    assert_screen('global-config-usb-open');

    assert_and_click('global-config-switch-to-updates');
    assert_screen('global-config-updates-open');

    assert_and_click('global-config-switch-to-splitgpg');
    assert_screen('global-config-splitgpg-open');

    assert_and_click('global-config-switch-to-clipboard');
    assert_screen('global-config-clipboard-open');

    assert_and_click('global-config-switch-to-file');
    assert_screen('global-config-file-open');

    assert_and_click('global-config-switch-to-url');
    assert_screen('global-config-url-open');

    assert_and_click('global-config-switch-to-thisdevice');
    assert_screen('global-config-thisdevice-open');

    assert_and_click('global-config-switch-to-general');
    assert_screen('global-config-general-open');

    # change something
    assert_and_click('global-config-open-clockvm');
    assert_and_click('global-config-clockvm-select-sysusb');

    # try to switch pages
    assert_and_click('global-config-switch-to-url');
    assert_and_click('global-config-cancel-changes');
    assert_screen('global-config-general-open');

    assert_and_click('global-config-switch-to-file');
    assert_and_click('global-config-discard-changes');
    assert_screen('global-config-file-open');

    # exit
    assert_and_click('global-config-cancel');

    # open at template repos
    if (!check_var("VERSION", "4.2")) {
        x11_start_program('qubes-global-config --open-at updates#template_repositories', target_match => 'qubes-global-config-template-repos');
        assert_screen('global-config-open-at-template-repositories');
        assert_and_click('global-config-switch-to-general');
        assert_and_click('global-config-cancel');
    }

    # open docs
    if (!check_var("VERSION", "4.2")) {
        x11_start_program('qubes-global-config --open-at basics#memory_balancing',
        target_match =>
        'qubes-global-config-window-management');
        assert_and_click('global-config-open-docs');
        assert_and_click('global-config-close-docs', timeout => 90);
        # exit
        assert_and_click('global-config-cancel');
    }

    x11_start_program('qubes-global-config');

    select_root_console;
    my $old_clockvm = script_output('qubes-prefs clockvm');

    if ($old_clockvm ne "sys-net") {
        die("Incorrect initial clockvm");
    }

    select_console('x11', await_console=>0);

    # change clock vm
    assert_and_click('global-config-open-clockvm');
    assert_and_click('global-config-clockvm-select-sysusb');
    assert_and_click('global-config-click_ok');

    select_root_console;

    my $new_clockvm = script_output('qubes-prefs clockvm');

    if ($new_clockvm ne "sys-usb") {
        die("Failed to change clockvm");
    }

    assert_script_run("qubes-prefs clockvm sys-net");
    select_console('x11', await_console=>0);

    if (!check_var("VERSION", "4.2")) {
        x11_start_program('qubes-global-config --open-at thisdevice', target_match => 'qubes-global-config-openat-thisdevice');
    } else {
        x11_start_program('qubes-global-config');
        assert_and_click('global-config-switch-to-thisdevice');
    }
    assert_screen('global-config-thisdevice-open');

    assert_and_click('global-config-copy-hcl-to-global-clipboard');
    assert_and_click('clipboard-widget-open');
    assert_and_click('clipboard-widget-copied-from-dom0');

    assert_and_click('global-config-cancel');
    # twice, because the focus will be on the widget the first time around
    assert_and_click('global-config-cancel');
}

sub post_fail_hook {
    my ($self) = @_;
    select_console('x11', await_console=>0);
    if (!check_screen('desktop', 5)) {
        send_key('alt-f4');
    }
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;
