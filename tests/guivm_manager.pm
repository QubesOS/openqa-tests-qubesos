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


sub run {
    select_console('x11');
    assert_screen "desktop";

    # This has two purposes:
    # 1. Test if qubes manager works
    # 2. Generate menu (#5804)
    assert_and_click("menu");
    assert_and_click("menu-qubes-tools");
    assert_and_click("menu-qubes-manager");
    assert_screen("qubes-qube-manager", timeout => 120);

    # open work VM settings
    assert_and_click("manager-work", button => 'right');
    assert_and_click("manager-vm-settings");
    assert_and_click("vm-settings-applications");
    assert_and_click("vm-settings-applications-refresh");
    # wait until refresh backs to normal (finish refreshing)
    assert_screen("vm-settings-applications-refresh", timeout => 300);
    # wait some more for the VMs to shutdown
    sleep(20);
    assert_and_click("vm-settings-ok");

    send_key("alt-s");
    sleep(1);
    send_key("e");

    assert_screen "desktop";
}

sub post_fail_hook {
    my ($self) = @_;
    select_console('x11');
    send_key('esc');
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

