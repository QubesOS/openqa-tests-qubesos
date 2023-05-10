
# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2019 Marta Marczykowska-Górecka <marmarta@invisiblethingslab.com>
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

    # make sure there's something to update

    select_root_console();
    script_run('qvm-features --unset `qubes-prefs default-template` updates-available;qvm-features `qubes-prefs default-template` updates-available 1;qvm-features dom0 updates-available 1');
    select_console('x11');

    # wait for update alert to appear
    assert_screen('qui-updates-update-available', 120);

    # open the widget
    assert_and_click('qui-updates-widget-open', timeout => 20);

    # launch the updater
    assert_and_click('qubes-update-launch-updater', timeout => 20);
    if (check_var("VERSION", "4.1")) {
        assert_and_click('qubes-update-enable-for-all', timeout => 20);
    }

    assert_and_click('qubes-update-deselect-dom0', timeout => 20);
    assert_and_click('qubes-update-select-dom0', timeout => 20);

    # go to next, then cancel
    assert_and_click('qubes-update-next', timeout => 20);
    assert_and_click('qubes-update-cancel', timeout => 20);

    assert_and_click('qubes-update-cancelling');
    if (check_var("VERSION", "4.1")) {
        assert_and_click('qubes-update-next', timeout => 20);
    }
    assert_and_click('qubes-update-finish', timeout => 1200);

    # try launching the updater from console
    x11_start_program('qubes-update-gui');

    assert_and_click('qubes-update-cancel');

    assert_screen('desktop-empty');

}

sub post_fail_hook {
    my ($self) = @_;
    select_console('x11');
    send_key('esc');
    if (!check_screen('desktop', 5)) {
        send_key('alt-f4');
    }
    save_screenshot;
    $self->SUPER::post_fail_hook;
};

1;

# vim: set sw=4 et:

