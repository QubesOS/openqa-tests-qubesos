# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2023 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

    $self->select_gui_console;
    assert_screen "desktop";
    x11_start_program('xterm');
    become_root;
    curl_via_netvm;
    send_key('alt-f10');

    open EXTRA_TARBALL, "tar cz -C " . testapi::get_required_var('CASEDIR') . " extra-files|base64|" or die "failed to create tarball";
    my $tarball = do { local $/; <EXTRA_TARBALL> };
    close(EXTRA_TARBALL);
    save_tmp_file('extra-files.tar.gz.b64', $tarball);

    assert_script_run("curl " . autoinst_url('/files/extra-files.tar.gz.b64') . " | base64 -d | tar xz -C /root");
    assert_script_run('/bin/cp -a /root/extra-files/system-tests /srv/salt/');

    assert_script_run("(set -o pipefail; qubesctl --skip-dom0 --max-concurrency=1 --templates --show-output state.sls system-tests.pipewire 2>&1 | tee /tmp/pipewire-install.log)", timeout => 1800);
    upload_logs('/tmp/pipewire-install.log', failok => 1);

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
    upload_logs('/tmp/pipewire-install.log', failok => 1);
};

1;

# vim: set sw=4 et:
