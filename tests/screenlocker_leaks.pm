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
use serial_terminal;

# WARNING: this test depends on simple_gui_apps.pm (which adds xterm to the menu)

sub run {
    my ($self) = @_;

    select_root_console();
    # install mate-notification-daemon, as it triggers the issue more reliably than xfce4-notifyd
    assert_script_run('qvm-run -p -u root work "dnf -y install mate-notification-daemon || apt -y install mate-notification-daemon"', timeout => 180);
    $self->select_gui_console;

    # set xfce4-screenlocker to "blank" mode
    x11_start_program("env xfconf-query -c xfce4-screensaver -p /saver/mode -n -t int -s 0", valid => 0);

    $self->open_menu;
    assert_and_click("menu-vm-work");
    assert_and_click("menu-vm-xterm");

    assert_screen('work-xterm');

    type_string("for i in `seq 60`; do notify-send test; sleep 1; done\n");
    # wait for the first notification
    assert_screen("notification-test");
    # lock the screen
    if (check_var("DESKTOP", "kde")) {
        send_key('super-l');
    } elsif (check_var("DESKTOP", "i3")) {
        send_key('super-shift-O');
    } else {
        send_key('ctrl-alt-delete');
    }
    # wait for notifications to (potentially) appear
    sleep(3);
    assert_screen("screenlocker-blank");
    # wait for the above loop to end
    sleep(60);
    # and unlock
    send_key_until_needlematch('xscreensaver-prompt-with-chars', 'a', 20, 3);
    # remove 'aaa' and enter the actual passphrase
    send_key('backspace');
    send_key('backspace');
    send_key('backspace');
    type_password();
    send_key('ret');
    assert_and_click(['work-xterm', 'work-xterm-inactive']);
    type_string("exit\n");

    assert_screen("desktop");
}

sub post_fail_hook {
    my ($self) = @_;
    save_screenshot;
    $self->SUPER::post_fail_hook;
};

1;

# vim: set sw=4 et:

