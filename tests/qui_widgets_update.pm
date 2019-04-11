
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


sub run {
    # open global-settings
    select_console('x11');
    assert_screen "desktop";

    # make sure there's something to update

    select_console('root-virtio-terminal');
    script_run('qvm-features --unset fedora-29 updates-available;qvm-features fedora-29 updates-available 1;qvm-features dom0 updates-available 1');
    select_console('x11');

    # wait for update alert to appear
    assert_screen('qui-updates-update-available', 120);

    # open the widget
    assert_and_click('qui-updates-widget-open', 'left', 20);

    # launch the updater
    assert_and_click('qubes-update-launch-updater', 'left', 20);
    assert_and_click('qubes-update-enable-for-all', 'left', 20);

    assert_and_click('qubes-update-select-dom0', 'left', 20);
    assert_and_click('qubes-update-deselect-dom0', 'left', 20);

    # go to next, then cancel
    assert_and_click('qubes-update-next', 'left', 20);
    assert_and_click('qubes-update-cancel', 'left', 20);

    assert_screen('qubes-update-cancelling');
    assert_and_click('qubes-update-finish', 'left', 900);

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

