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
    # open policy editor in-blanco
    select_console('x11');
    assert_screen "desktop";
    x11_start_program('qubes-new-qube');

    assert_and_click('new-qube-select-name');
    type_string('createtest');


    # make a qube with no firefox, selected calculator, no network
    # settings launched after creation
    assert_and_click('new-qube-launch-settings');
    assert_and_click('new-qube-remove-firefox');
    assert_and_click('new-qube-add-app');
    assert_and_click('new-qube-add-app-about-xfce');
    send_key('esc');
    assert_and_click('new-qube-open-network-settings');
    assert_and_click('new-qube-network-none');
    assert_and_click('new-qube-close-network-settings');
    assert_and_click('new-qube-open-label');
    assert_and_click('new-qube-label-select-blue');

    send_key('alt-r');
    assert_and_click('new-qube-success');

    assert_screen('new-qube-createtest-settings');
    assert_and_click('new-qube-createtest-settings-switch-apps');
    assert_screen('new-qube-createtest-settings-check-apps');

    send_key('esc');

    x11_start_program('qubes-new-qube');

    assert_and_click('new-qube-select-name');
    type_string('createtest2');

    assert_and_click('new-qube-switch-to-template');
    assert_and_click('new-qube-launch-settings');
    assert_and_click('new-qube-open-advanced');
    assert_and_click('new-qube-advanced-provide-network');

    send_key('alt-r');
    assert_and_click('new-qube-success');

    assert_screen('new-qube-createtest2-settings');
    assert_and_click('new-qube-createtest2-settings-switch-advanced');
    assert_screen('new-qube-createtest2-settings-check-advanced');

    send_key('esc');

    x11_start_program('qubes-new-qube');

    assert_and_click('new-qube-switch-to-standalone');

    assert_and_click('new-qube-select-name');
    type_string('createtest3');

    assert_and_click('new-qube-launch-settings');
    assert_and_click('new-qube-clone-from');
    assert_and_click('new-qube-clone-from-open');
    assert_and_click('new-qube-clone-from-select-debian');
    assert_and_click('new-qube-remove-firefox-esr');

    send_key('alt-r');
    assert_and_click('new-qube-success');

    assert_screen('new-qube-createtest3-settings');
    assert_and_click('new-qube-createtest-settings-switch-apps');
    assert_screen('new-qube-createtest3-settings-check-apps');

    send_key('esc');

    x11_start_program('qubes-new-qube');

    assert_and_click('new-qube-switch-to-named-disp');

    assert_and_click('new-qube-select-name');
    type_string('createtest4');

    assert_and_click('new-qube-launch-settings');
    send_key('alt-r');
    assert_and_click('new-qube-success');

    assert_screen('new-qube-createtest4-settings');

    send_key('esc');

}

sub post_fail_hook {
    my ($self) = @_;
    select_console('x11');
    if (!check_screen('desktop', 5)) {
        send_key('alt-f4');
    }
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;
