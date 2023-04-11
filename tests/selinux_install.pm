# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2022 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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
    send_key('alt-f10');
    curl_via_netvm;

    my @templates = split / /, get_var("SELINUX_TEMPLATES");

    foreach (@templates) {
        my $template = $_;

        assert_script_run("qvm-start $template");
        assert_script_run("(set -o pipefail; qvm-run -p -u root $template 'dnf install -y selinux-policy' 2>&1 | tee -a /tmp/selinux-install.log)", timeout => 300);
        # switch to permissive until fs get relabeled
        assert_script_run("(set -o pipefail; qvm-run -p -u root $template 'sed -i -e \"s/^SELINUX=.*/SELINUX=permissive/\" /etc/selinux/config' 2>&1 | tee -a /tmp/selinux-install.log)", timeout => 300);
        assert_script_run("qvm-shutdown --wait $template", timeout => 60);
        assert_script_run("qvm-prefs $template qrexec_timeout 3600");
        assert_script_run("qvm-prefs $template kernelopts \"\$(qvm-prefs $template kernelopts) selinux=1 security=selinux\"");
        # this will "fail" as the template will shutdown itself after relabel
        script_run("time qvm-start $template", timeout => 3600);
        # just in case, but it should shutdown on its own already
        assert_script_run("qvm-shutdown --wait $template", timeout => 60);
        upload_logs("/var/log/xen/console/guest-$template.log");
        # then finally set to enforcing
        assert_script_run("(set -o pipefail; qvm-run -p -u root $template 'sed -i -e \"s/^SELINUX=.*/SELINUX=enforcing/\" /etc/selinux/config' 2>&1 | tee -a /tmp/selinux-install.log)", timeout => 300);
        assert_script_run("qvm-shutdown --wait $template", timeout => 60);
        upload_logs("/tmp/selinux-install.log");
    }
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { fatal => 1, milestone => 1 };
}


sub post_fail_hook {
    my $self = shift;

    $self->SUPER::post_fail_hook();
    upload_logs('/tmp/selinux-install.log', failok => 1);
};

1;

# vim: set sw=4 et:
