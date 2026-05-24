# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2026 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

    $self->select_gui_console;

    # set xfce4-screenlocker to "blank" mode
    x11_start_program("env xfconf-query -c xfce4-screensaver -p /saver/mode -n -t int -s 0", valid => 0);

    x11_start_program("loginctl lock-session", valid => 0);
    # wait for notifications to (potentially) appear
    sleep(3);
    assert_screen("screenlocker-blank");
    # and unlock
    send_key_until_needlematch('xscreensaver-prompt-with-chars', 'a', 20, 3);
    # remove 'aaa' and enter the actual passphrase
    send_key('backspace');
    send_key('backspace');
    send_key('backspace');
    type_password();
    send_key('ret');

    assert_screen("desktop");
}

sub post_fail_hook {
    my ($self) = @_;
    save_screenshot;
    $self->SUPER::post_fail_hook;
};

1;

# vim: set sw=4 et:

