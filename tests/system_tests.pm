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
    my $failed = 0;

    select_console('x11');
    x11_start_program('xterm');
    send_key('alt-f10');
    curl_via_netvm;

    assert_script_run("sudo cat /root/extra-files/convert_junit.py >convert_junit.py");
    # until https://github.com/nose-devs/nose2/pull/412 gets merged
    assert_script_run("sudo patch /usr/lib/python3*/site-packages/nose2/plugins/junitxml.py /root/extra-files/nose2-junit-xml-log-skip-reason.patch");

    # don't let logrotate restart qubesd in the middle of the tests
    assert_script_run("sudo systemctl stop crond");

    if (get_var('TEST_TEMPLATES')) {
        assert_script_run("export QUBES_TEST_TEMPLATES='" . get_var('TEST_TEMPLATES') . "'");
    }

    foreach ('QUBES_TEST_EXTRA_INCLUDE', 'QUBES_TEST_EXTRA_EXCLUDE') {
        if (get_var($_)) {
            assert_script_run("export $_='" . get_var($_) . "'");
        }
    }

    if (check_var('VERBOSE_LIBVIRT', '1')) {
        assert_script_run('echo log_level = 1 | sudo tee -a /etc/libvirt/libvirtd.conf');
        assert_script_run('echo \'log_filters = "3:event 3:object 3:net"\' | sudo tee -a /etc/libvirt/libvirtd.conf');
        assert_script_run('sudo systemctl restart libvirtd');
    }

    my $testfunc = <<ENDFUNC;
testfunc() {
    rm -f nose2-junit.xml
    cmd_prefix=
    if [[ "\$1" = "qubes.tests."* ]]; then
        sudo systemctl stop qubesd
        cmd_prefix="sudo -E"
    fi
    #sudo -E script -e -c "python3 -m qubes.tests.run \$1" tests-\$1.log
    \$cmd_prefix script -e -c "nose2 -v --plugin nose2.plugins.loader.loadtests --plugin nose2.plugins.junitxml -X \$1" tests-\$1.log
    retval=\$?
    sudo systemctl start qubesd
    python3 convert_junit.py nose2-junit.xml nose2-junit-\$1.xml
    return \$retval
}
ENDFUNC
    chop($testfunc);
    assert_script_run($testfunc);
    foreach (split / /, get_var('SYSTEM_TESTS')) {
        my ($test, $timeout) = split /:/;
        $timeout //= 3600;
        my $ret = script_run("testfunc $test", $timeout);
        if (!defined $ret) {
            die("Tests $_ timed out");
        } elsif ($ret != 0) {
            record_info('Fail', "Tests $test failed (exit code $ret), details reported separately", result => 'fail');
            $failed = 1;
        }
        # try to close any popups left from the test, focust _must_ be on xterm window
        while (check_screen('qrexec-confirmation-cancel', 1)) {
            assert_and_click('qrexec-confirmation-cancel');
            sleep(1);
        }
        send_key('esc');
        send_key('esc');
        send_key('esc');
        send_key('ctrl-c');
        send_key('ret');
        x11_start_program('xdotool search --class ^xterm windowfocus', valid => 0);

        upload_logs("tests-$test.log");
        # upload also original xml, if something goes wrong with conversion
        upload_logs("nose2-junit.xml");
        parse_extra_log('JUnit', "nose2-junit-$test.xml");
        # help debugging tests
        unless (script_run "sudo tar czf /tmp/objgraphs-$test.tar.gz /tmp/objgraph-*") {
            upload_logs "/tmp/objgraphs-$test.tar.gz";
            script_run "sudo rm -f /tmp/objgraph-*";
        }
        if (script_run('pidof -x qvm-start-gui || pidof -x qvm-start-daemon')) {
            record_soft_failure('qvm-start-gui crashed');
        }
    }
    if ($failed) {
        die "Some tests failed";
    }
}

1;

# vim: set sw=4 et:
