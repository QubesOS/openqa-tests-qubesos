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
use serial_terminal;

sub run {
    my ($self) = @_;
    my $failed = 0;

    save_screenshot;
    select_root_console();
    enable_dom0_network_netvm() unless $self->{network_up};
    $self->save_and_upload_log('journalctl -b', 'journalctl.log', {timeout => 120});
    $self->save_and_upload_log('sudo -u user journalctl --user -b', 'user-journalctl.log', {timeout => 120});
    unless (script_run "tar czf /tmp/var_log.tar.gz --exclude=journal /var/log; ls /tmp/var_log.tar.gz") {
        upload_logs "/tmp/var_log.tar.gz";
    }
}

sub test_flags {
    # 'fatal'          - abort whole test suite if this fails (and set overall state 'failed')
    # 'ignore_failure' - if this module fails, it will not affect the overall result at all
    # 'milestone'      - after this test succeeds, update 'lastgood'
    # 'norollback'     - don't roll back to 'lastgood' snapshot if this fails
    return { ignore_failure => 1 };
}

1;
