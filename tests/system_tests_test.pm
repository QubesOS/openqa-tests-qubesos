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
use networking;

sub run {
    my ($self) = @_;

    select_console('x11');
    x11_start_program('xterm');
    send_key('alt-f10');
type_string("sudo -s\n");
    enable_dom0_network_netvm;
type_string("exit\n");

    assert_script_run("curl " . autoinst_url('/assets/other/convert_junit.py') . " >convert_junit.py");
    assert_script_run("curl " . autoinst_url('/assets/other/example2-nose2-junit.xml') . " >nose2-junit.xml");

    foreach (split / /, get_var('SYSTEM_TESTS')) {
        my ($test, $timeout) = split /:/;
        $timeout //= 3600;
        #my $ret = script_run("testfunc $test", $timeout);
        my $ret = 1;
        #upload_logs("tests-$test.log");
        if (!defined $ret) {
            die("Tests $_ timed out");
        } elsif ($ret != 0) {
            record_info('fail', "Tests $test failed", result => 'fail');
            $self->record_testresult('fail');
        }
        # try to close any popups left from the test, focust _must_ be on xterm window
        send_key('esc');
        send_key('esc');
        send_key('esc');
        send_key('ctrl-c');
        send_key('ret');
        x11_start_program('xdotool search --class ^xterm windowfocus', valid => 0);
        assert_script_run('python3 convert_junit.py nose2-junit.xml nose2-junit.xml');
        parse_extra_log("JUnit", "nose2-junit.xml");
    }
}

1;

# vim: set sw=4 et:

