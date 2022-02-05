
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
    x11_start_program('qubes-vm-create');

    # input name
    type_string('testqube');

    # choose a label
    assert_and_click('qubes-vm-create-label-open');
    assert_and_click('qubes-vm-create-label-choose-blue');

    # choose type
    assert_and_click('qubes-vm-create-type-open');
    assert_and_click('qubes-vm-create-type-appvm');

    # open template
    assert_and_click('qubes-vm-create-template-open');
    assert_screen('qubes-vm-create-templates-opened');
    send_key('esc');

    # open networking
    assert_and_click('qubes-vm-create-networking-open');
    assert_screen('qubes-vm-create-networking-opened');
    send_key('esc');

    # launch settings
    assert_and_click('qubes-vm-create-launch-settings');

    # click ok
    assert_and_click('qubes-vm-create-ok');

    # see if settings launched
    assert_screen('qubes-vm-create-settings-launched', 60);
    send_key('esc');

    # see if screen empty
    assert_screen('desktop');

    # launch again
    x11_start_program('qubes-vm-create');

    # click cancel
    assert_and_click('qubes-vm-create-cancel');

    # see if screen empty
    assert_screen('desktop');

    # launch again
    x11_start_program('qubes-vm-create');

    # click exit button
    assert_and_click('qubes-vm-create-exit');
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

