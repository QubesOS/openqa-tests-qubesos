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

    if (get_var('TEST_TEMPLATES') && !(get_var("TEST_TEMPLATES") =~ m/whonix/)) {
        record_info('skip', "only selected templates test requested and whonix is not one of them");
        return;
    }

    my @whonix_vms = split(/\n/, script_output("qvm-ls --raw-list|grep whonix"));
    # sort sys-whonix first
    @whonix_vms = sort {
        if ($a == 'sys-whonix') { return -1; }
        if ($b == 'sys-whonix') { return  1; }
        return $a cmp $b;
    } @whonix_vms;

    assert_script_run('set -o pipefail');

    foreach (@whonix_vms) {
        next if /-dvm/;
        my $ret = script_run("qvm-run -ap $_ 'LC_ALL=C whonixcheck --verbose --leak-tests --cli' | tee whonixcheck-$_.log", 500);
        upload_logs("whonixcheck-$_.log");
        if ($ret != 0) {
            record_info('fail', "Whonixcheck for $_ failed", result => 'fail');
            $self->record_testresult('fail');
        }
        # shutdown all except sys-whonix
        unless (/sys-whonix/) {
            assert_script_run("qvm-shutdown --wait $_", timeout => 90);
        }
    }
    type_string("exit\n");
}

1;

# vim: set sw=4 et:
