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

# WARNING: this test depends on simple_gui_apps.pm (which adds xterm to the menu)

sub run {
    select_console('root-virtio-terminal');
    # install mate-notification-daemon, as it triggers the issue more reliably than xfce4-notifyd
    assert_script_run('qvm-run -p -u root work "dnf -y install mate-notification-daemon || apt -y install mate-notification-daemon"', timeout => 120);
    select_console('x11');

    # start xscreensaver (killed in the test startup); the space at the end is
    # intentional, otherwise it autocompletes to xscreensaver-demo
    x11_start_program('xscreensaver ', valid => 0);

    assert_and_click("menu");
    assert_and_click("menu-vm-work");
    assert_and_click("menu-vm-xterm");

    assert_screen('work-xterm');

    type_string("for i in `seq 60`; do notify-send test; sleep 1; done\n");
    # wait for the first notification
    assert_screen("notification-test");
    # lock the screen
    send_key('ctrl-alt-delete');
    # wait for notifications to (potentially) appear
    sleep(3);
    assert_screen("screenlocker-blank");
    # wait for the above loop to end
    sleep(60);
    # and unlock
    type_password();
    send_key('ret');
    assert_and_click(['work-xterm', 'work-xterm-inactive']);
    type_string("exit\n");

    x11_start_program('pkill xscreensaver', valid => 0);
    assert_screen("desktop");
}

sub post_fail_hook {
    my ($self) = @_;
    select_console('x11');
    save_screenshot;
    $self->SUPER::post_fail_hook;
};

1;

# vim: set sw=4 et:

