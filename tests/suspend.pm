# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2019 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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
    assert_screen "desktop";
    x11_start_program('xterm');
    curl_via_netvm;

    assert_script_run('sudo dmesg -n 8');
    assert_script_run('sudo rtcwake -n -s 30');
    assert_script_run('sudo systemctl suspend');
    sleep(60);
    if (check_var('BACKEND', 'generalhw')) {
        power('on');
    }
    sleep(15);
    wait_screen_change {
        send_key 'ctrl';
    };
    send_key('ctrl');
    assert_screen('xscreensaver-prompt');
    # unlock screen
    type_string($password);
    send_key('ret');
    sleep(10);
    
    # now verify if everything is right
    assert_script_run('true');

    # log some info
    script_run('xl list');
    script_run('virsh -c xen list --all');

    # resumed and qrexec really works
    assert_script_run('qvm-run -p sys-net true');
    assert_script_run('! qvm-check sys-usb || qvm-run -p sys-usb true');
    assert_script_run('qvm-run -p sys-firewall true');

    # check network
    assert_script_run('qvm-run -p sys-firewall "curl https://www.qubes-os.org/" >/dev/null');

    # if whonix is there, extra checks
    if (script_run('qvm-check sys-whonix') == 0) {
        assert_script_run('set -o pipefail');
        my $ret = script_run("qvm-run -ap sys-whonix 'LC_ALL=C whonixcheck --verbose --leak-tests --cli' | tee whonixcheck-sys-whonix.log", 500);
        upload_logs("whonixcheck-sys-whonix.log");
        if ($ret != 0) {
            record_info('fail', "Whonixcheck for sys-whonix failed", result => 'fail');
            $self->record_testresult('fail');
        }
    }
    type_string("exit\n");
}

1;

# vim: set sw=4 et:
