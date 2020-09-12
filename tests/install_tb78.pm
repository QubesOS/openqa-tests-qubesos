# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2020 Frédéric Pierret <frederic.pierret@qubes-os.org>
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
    become_root;
    curl_via_netvm;

    assert_script_run('qvm-run -p fedora-32 "sudo dnf copr enable -y fepitre/thunderbird-78" | tee install_tb78.log');
    assert_script_run('(qvm-run -p fedora-32 "sudo dnf update -y thunderbird" 2>&1 | tee -a install_tb78.log)', timeout => 600);
    assert_script_run('(qvm-shutdown --wait fedora-32 2>&1 | tee -a install_tb78.log)', timeout => 300);
    upload_logs("install_tb78.log");

    type_string("exit\n");
    type_string("exit\n");
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
    upload_logs('/tmp/install_tb78.log', failok => 1);
};

1;

# vim: set sw=4 et:
