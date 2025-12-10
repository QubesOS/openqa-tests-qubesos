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
use OpenQA::Test::RunArgs;

sub run {
    my ($self, $args) = @_;

    if (check_var('SKIP_INSTALL', '1')) {
        return;
    }

    my $whonix_gateway = "sys-whonix";
    if (exists $args->{whonix_gw_override}) {
        $whonix_gateway = $args->{whonix_gw_override};
    } else {
    }

    $self->select_gui_console;

    my $start_whonix_gw_cmd = sprintf "qvm-start %s", $whonix_gateway;
    x11_start_program($start_whonix_gw_cmd, valid => 0);
    if (!check_screen(['whonix-connected', 'whonix-firstrun', 'whonix-news'], 120)) {
        # no firstrun wizard? maybe already accepted - verify it
        my $run_whonixcheck_cmd = sprintf "qvm-run %s 'whonixcheck --gui'", $whonix_gateway;
        x11_start_program($run_whonixcheck_cmd, valid => 0);
        assert_screen('whonix-connected', timeout => 60);
    }

    if (match_has_tag('whonix-connected') or match_has_tag('whonix-news')) {
        # already configured and connected, wait for notification to disappear
        assert_screen('no-notifications');
        # this may show up some time after connecting...
        if (check_screen("whonix-news", timeout => 300)) {
            assert_and_click("whonix-news");
        }
        return;
    }

    if (match_has_tag('whonixcheck-time-unstable')) {
        send_key('ret');
        wait_still_screen;
    }
    assert_and_click('whonix-firstrun');
    assert_and_click('whonix-firstrun-confirm');
    assert_screen "whonix-connecting";
    assert_screen "whonix-connected", timeout => 150;
    if (match_has_tag('whonix-connected-wizard')) {
        send_key('ret');
    }
    while (check_screen(['whonixcheck-time-unstable', "whonix-connecting", "whonix-news"], timeout => 120)) {
        if (match_has_tag('whonixcheck-time-unstable')) {
            send_key('ret');
            wait_still_screen;
        }
        if (match_has_tag("whonix-connecting")) {
            assert_screen("whonix-connected", 150);
        }
        # this may show up some time after connecting...
        if (match_has_tag("whonix-news")) {
            assert_and_click("whonix-news");
            wait_still_screen;
        }
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
