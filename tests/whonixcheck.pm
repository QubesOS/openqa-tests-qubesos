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
    my $failed = 0;

    if (get_var('TEST_TEMPLATES') && !(get_var("TEST_TEMPLATES") =~ m/whonix/)) {
        record_info('skip', "only selected templates test requested and whonix is not one of them");
        return;
    }

    $self->select_gui_console;
    assert_screen "desktop";
    x11_start_program('xterm');
    curl_via_netvm;

    # an image saved hours earlier has an expired consensus; sdwdate then gives up
    my $consensus_stale = script_run(q{qvm-run -pu root sys-whonix 'f=/var/lib/tor/cached-microdesc-consensus; for i in $(seq 30); do test ! -e $f && exit 0; test $(date -u -d "$(sed -n "s/^valid-until //p" $f)" +%s) -gt $(date -u +%s) && exit 0; sleep 10; done; exit 1'}, timeout => 330);
    record_info('consensus', 'Tor consensus in sys-whonix still expired after 300 s') if $consensus_stale;
    if (!$consensus_stale && script_run(q{qvm-run -pu root sys-whonix 'for i in $(seq 30); do test -e /run/sdwdate/first_success && exit 1; journalctl -b -u sdwdate | grep -q "Giving up" && break; sleep 5; done; journalctl -b -u sdwdate | grep -q "Tor Consensus Time Sanity Check: fast"'}, timeout => 180) == 0) {
        record_soft_failure('sdwdate in sys-whonix gave up on the expired Tor consensus; restarting it');
        $self->save_and_upload_log('qvm-run -pu root sys-whonix journalctl -b -u sdwdate', 'sdwdate-before-restart-sys-whonix.log', {timeout => 120});
        script_run(q{qvm-run -pu root sys-whonix 'systemctl restart sdwdate && timeout 300 sh -c "until test -e /run/sdwdate/first_success; do sleep 5; done"'}, timeout => 330);
    }

    my @whonix_vms = map { s/\r//r } split(/\n/, script_output("qvm-ls --raw-list|grep whonix"));
    # sort sys-whonix first
    @whonix_vms = sort {
        if ($a eq 'sys-whonix') { return -1; }
        if ($b eq 'sys-whonix') { return  1; }
        return $a cmp $b;
    } @whonix_vms;

    assert_script_run('set -o pipefail');

    foreach (@whonix_vms) {
        next if /-dvm/;
        s/\r//;
        script_run("qvm-run -ap $_ systemctl --wait is-system-running </dev/null", timeout => 180);
        my $ret = script_run("qvm-run -ap $_ 'LC_ALL=C whonixcheck --verbose --leak-tests --cli' 2>&1 </dev/null | tee whonixcheck-$_.log", 500);
        upload_logs("whonixcheck-$_.log");
        if ($ret != 0) {
            record_info('fail', "Whonixcheck for $_ failed", result => 'fail');
            $failed = 1;
            $self->save_and_upload_log("qvm-run -pu root $_ journalctl -b", "journalctl-$_.log", {timeout => 120});
            $self->save_and_upload_log("qvm-run -pu root $_ journalctl -b -1", "journalctl-previous-$_.log", {timeout => 120});
        }
        # shutdown all except sys-whonix
        unless (/sys-whonix/) {
            assert_script_run("qvm-shutdown --wait $_", timeout => 90);
        }
    }
    type_string("exit\n");
    die "systemcheck failed" if ($failed);
}

1;

# vim: set sw=4 et:
