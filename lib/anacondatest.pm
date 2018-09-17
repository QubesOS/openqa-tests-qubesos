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

package anacondatest;
use base 'basetest';
use strict;
use testapi;
use networking;

sub new {
    my ($class, $args) = @_;
    my $self = $class->SUPER::new($args);
    $self->{network_up} = 0;
    return $self;
}

sub post_fail_hook {
    my $self = shift;

    # if error dialog is shown, click "report" - it then creates directory structure for ABRT
    my $has_traceback = 0;
    if (check_screen "anaconda-error", 10) {
        assert_and_click "anaconda-error-report";
        $has_traceback = 1;
    } elsif (check_screen "anaconda-text-error", 10) {  # also for text install
        type_string "1\n";
        $has_traceback = 1;
    }

    save_screenshot;
    select_console('install-shell');
    # during installation Xen doesn't have console=com1
    $testapi::serialdev = 'ttyS0';
    if (!$self->{network_up}) {
        enable_dom0_network_no_netvm();
        $self->{network_up} = 1;
    }
    assert_script_run('cat /tmp/anaconda.log');
    upload_logs "/tmp/X.log", failok=>1;
    upload_logs "/tmp/anaconda.log", failok=>1;
    upload_logs "/tmp/packaging.log", failok=>1;
    upload_logs "/tmp/storage.log", failok=>1;
    upload_logs "/tmp/syslog", failok=>1;
    upload_logs "/tmp/program.log", failok=>1;
    upload_logs "/tmp/dnf.log", failok=>1;
    upload_logs "/tmp/dnf.librepo.log", failok=>1;
    upload_logs "/tmp/dnf.rpm.log", failok=>1;

    if ($has_traceback) {
        # Upload Anaconda traceback logs
        script_run "tar czf /tmp/anaconda_tb.tar.gz /tmp/anaconda-tb-*";
        upload_logs "/tmp/anaconda_tb.tar.gz";
    }

    # Upload all ABRT logs (if there are any)
    unless (script_run 'test -n "$(ls -A /var/tmp)" && tar czf /var/tmp/var_tmp.tar.gz /var/tmp') {
        upload_logs "/var/tmp/var_tmp.tar.gz";
    }

    # Upload /var/log
    unless (script_run "tar czf /tmp/var_log.tar.gz /var/log") {
        upload_logs "/tmp/var_log.tar.gz";
    }

    # Upload anaconda core dump, if there is one
    unless (script_run "ls /tmp/anaconda.core.* && tar czf /tmp/anaconda.core.tar.gz /tmp/anaconda.core.*") {
        upload_logs "/tmp/anaconda.core.tar.gz";
    }
}

sub test_flags {
    # 'fatal'          - abort whole test suite if this fails (and set overall state 'failed')
    # 'ignore_failure' - if this module fails, it will not affect the overall result at all
    # 'milestone'      - after this test succeeds, update 'lastgood'
    # 'norollback'     - don't roll back to 'lastgood' snapshot if this fails
    return { fatal => 1 };
}

1;
# vim: sw=4 et ts=4:
