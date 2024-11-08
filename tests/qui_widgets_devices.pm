
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
    my ($self) = @_;

    # open global-settings
    $self->select_gui_console;
    assert_screen "desktop";

    # check if widget opened, open it
    assert_and_click('qui-devices-open', timeout => 20);
    assert_screen('qui-devices-opened');

    # close and open again
    send_key('esc');
    assert_and_click('qui-devices-open', timeout => 20);

    if (check_screen('qui-devices-mic-selected')) {
        # mic already selected, open submenu
        send_key('right');
    } else {
        # open a device
        send_key('down');
    }
    assert_screen('qui-devices-dev-opened', timeout => 20);

    # close the widget
    send_key('esc');
}

sub post_fail_hook {
    my ($self) = @_;
    $self->select_gui_console;
    send_key('esc');
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

