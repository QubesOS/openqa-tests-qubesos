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

    # open Tor Browser in anon-whonix 
    assert_and_click("menu");
    assert_and_click("menu-vm-anon-whonix");
    assert_and_click("menu-tor-browser");

    assert_screen("anon-whonix-tor-browser", timeout => 90);
    # wait for full startup
    sleep(2);
    assert_and_click("tor-browser-address-bar");
    type_string("https://check.torproject.org/");
    send_key("ret");
    assert_screen("tor-browser-ipcheck-ok");
    send_key("ctrl-q");
    wait_still_screen();
    assert_screen("desktop-clear");
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
