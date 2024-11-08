
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
    my ($self) = @_;

    # open global-settings
    $self->select_gui_console;
    assert_screen "desktop";

    # run xterm
    x11_start_program('xterm');
    # check if domains notify about start
    assert_script_run("qvm-shutdown --wait work", 200);
    type_string("qvm-start work\n", 200);
    assert_screen('qui-notifications-domain-start', 200);
    assert_script_run('qvm-run work true');

    # check if devices notify about connecting
    assert_and_click('qui-devices-open', timeout => 20);
    if (!check_screen('qui-devices-mic-selected')) {
        # open a device
        send_key('down');
    }
    send_key('right');
    send_key('ret');
    assert_screen('qui-notification-device-attach', 60);

    # exit politely
    type_string("exit\n");
    assert_screen "desktop";

    # turn off work domain
    select_root_console();
    script_run('qvm-shutdown --wait work', 200);
    $self->select_gui_console;
}

sub post_fail_hook {
    my ($self) = @_;
    $self->select_gui_console;
    type_string("exit\n");
    x11_start_program('qvm-shutdown work');
    save_screenshot;
    $self->SUPER::post_fail_hook;
};

1;

# vim: set sw=4 et:

