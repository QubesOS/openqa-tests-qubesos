# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2018 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

    select_console('x11');
    # wait for "connection established" popup to disappear
    wait_still_screen(10, 50);
    if (!check_screen(['whonix-connected', 'whonix-firstrun'], 120)) {
        # no firstrun wizard? maybe already accepted
        # TODO: add a variable to configure it and fail if the wizard was
        # expected
        record_soft_failure('No Whonix firstrun wizard detected');
        return;
    }

    if (match_has_tag('whonix-connected')) {
        # already configured and connected
        return;
    }

    if (match_has_tag('whonixcheck-time-unstable')) {
        send_key('ret');
        wait_still_screen;
    }
    send_key('ret');
    wait_still_screen;
    if (check_screen('whonixcheck-time-unstable')) {
        send_key('ret');
        wait_still_screen;
    }
    send_key('tab');
    send_key('tab');
    send_key('ret');
    assert_screen "whonix-connecting";
    assert_screen "whonix-connected", timeout => 60;
    if (match_has_tag('whonix-connected-wizard')) {
        send_key('ret');
    }
    if (check_screen('whonixcheck-time-unstable')) {
        send_key('ret');
        wait_still_screen;
    }
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { milestone => 1 };
}

1;

# vim: set sw=4 et:
